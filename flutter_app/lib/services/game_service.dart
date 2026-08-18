import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'iap_service.dart';
import '../models/player.dart';
import '../utils/mail_status.dart';
import '../models/room.dart';
import '../models/game_state.dart';
import '../models/sk_game_state.dart';
import '../models/ll_game_state.dart';
import '../models/shop_visual.dart';
import '../models/mighty_game_state.dart';
import 'analytics_service.dart';
import 'network_service.dart';
import 'profile_store.dart';
import 'restore_sync_tracker.dart';
import 'sfx_service.dart';

enum AppDestination {
  lobby,
  waitingRoom,
  game,
  spectator,
  skGame,
  llGame,
  mightyGame,
}

/// A seat changing hands mid-match, for the announcement banner.
class SeatHandoff {
  /// True when a human took a bot's seat, false when a human handed theirs
  /// to a bot and left.
  final bool joined;
  final String playerName;

  /// Name of the bot now holding the seat. Empty on a join.
  final String botName;
  final int slot;

  const SeatHandoff({
    required this.joined,
    required this.playerName,
    required this.botName,
    required this.slot,
  });
}

class GameService extends ChangeNotifier {
  final NetworkService _network;
  StreamSubscription? _subscription;
  Timer? _dogClearTimer;
  Timer? _inquiryBannerTimer;
  Timer? _pushToggleTimer;
  int _pushPrefsLoadVersion = 0;
  final Map<String, DateTime> _roomInviteCooldowns = {};
  Completer<String?>? _shareInviteLinkCompleter;
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

  /// One-shot marker set when we initiate room entry (join/invite) and
  /// cleared when the first room_state arrives. Used to fire the
  /// `room_join` analytics event with accurate gameType/isRanked.
  String? _pendingRoomEntry;
  String currentRoomName = '';
  // Dynamic slot system: maxPlayers elements, null for empty slots
  List<Player?> roomPlayers = [null, null, null, null];
  bool isHost = false;
  bool isRankedRoom = false;
  int roomTurnTimeLimit = 30;
  int roomTargetScore = 1000;
  int roomMaxPlayers = 4;
  Set<int> roomBlockedSlots = <int>{};

  /// Tichu-only: host opted to randomize team assignment at startGame
  /// instead of using the fixed (0,2) vs (1,3) seat-to-team mapping.
  bool roomRandomSeating = false;

  /// Current room allows breaking into / walking out of a running match.
  bool roomAllowMidGameJoin = false;

  /// Bot-held seats in the current room — what a spectator could take over.
  int roomBotSeatCount = 0;

  /// The current room has a match running. Read from room state rather than
  /// [hasActiveGame], which is keyed on the player-side game state a spectator
  /// never receives — for them the hand lives in [spectatorGameState].
  bool roomGameInProgress = false;

  /// A spectator here can break into the running match right now.
  bool get canJoinInProgress =>
      isSpectator &&
      roomAllowMidGameJoin &&
      roomGameInProgress &&
      roomBotSeatCount > 0;

  /// Leaving right now would hand this seat to a bot and let the match carry
  /// on, rather than ending it for everyone.
  ///
  /// Not a separate action — the ordinary leave does this by itself in a room
  /// with the option on (the server converts every desertion route, including
  /// a 3-timeout kick). Screens read it to word the leave warning correctly.
  /// False when nobody else human is at the table, where the server ends the
  /// match instead rather than leave bots playing to an empty room.
  bool get canLeaveInProgress {
    if (isSpectator || !roomAllowMidGameJoin || !roomGameInProgress) {
      return false;
    }
    final otherHumans = roomPlayers
        .where((p) => p != null && !p.isBot && p.id != playerId)
        .length;
    return otherHumans > 0;
  }

  /// Skull King expansions active in the current room. Subset of
  /// `['kraken', 'white_whale', 'loot']`. Only meaningful when
  /// [currentGameType] is `skull_king`.
  List<String> roomSkExpansions = const [];

  /// Effective max players after host-blocked slots are excluded.
  int get effectiveRoomMaxPlayers => roomMaxPlayers - roomBlockedSlots.length;

  // Room list
  List<Room> roomList = [];
  // False until the first room_list message arrives (and reset on disconnect) so
  // the lobby can show a loading spinner instead of a premature "no rooms" state.
  bool roomListReceived = false;
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

  // Persistent card-view policy synced with the server. Values:
  //   'ask'           - prompt the player on every incoming request (default)
  //   'always_allow'  - server auto-grants without notifying the player
  //   'always_deny'   - server auto-rejects without notifying the player
  String cardViewPref = 'ask';

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
  // IAP gold products (server-driven; product_ids resolved at runtime, never
  // hardcoded in the client). Keyed list of {product_id, gold_amount,
  // bonus_gold, label_*}. Store price/currency is merged in by IapService.
  List<Map<String, dynamic>> goldProducts = [];
  bool goldProductsLoading = false;

  // Bank transfer, web only — there is no store to buy from in a browser, so
  // the shop shows an account number instead. Null until the server answers;
  // `enabled: false` (an admin who hasn't configured an account, or has taken
  // it down) is the same thing to the UI as never having asked.
  Map<String, dynamic>? bankDepositInfo;
  List<Map<String, dynamic>> shopItems = [];
  List<Map<String, dynamic>> inventoryItems = [];

  /// Server-driven visual cache for banners/titles/themes. Populated once
  /// per login via `requestVisualCatalog()`. Lookup by itemKey → ShopVisual
  /// so renderers can use admin-edited gradient angle/stops instead of
  /// hardcoded color pairs.
  Map<String, ShopVisual> visualCatalog = const {};
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

  /// Display name of the equipped title, and the equipped banner key. Both are
  /// on the profile payload too, but that is a cached fetch — equipping updates
  /// these immediately so previews and seats don't keep showing the old one.
  String? equippedTitleName;
  String? equippedBanner;

  // Own active profile-photo URL (null = default avatar). Set from
  // login_success and refreshed after a successful upload.
  String? myPhotoUrl;

  /// Resolve a (possibly relative) avatar URL into an absolute one against the
  /// active server host. Used by avatar widgets.
  String? resolvePhotoUrl(String? url) => _network.resolveMediaUrl(url);

  /// Photo that arrived with a chat line, by sender nickname.
  final Map<String, String> _chatPhotos = {};

  /// Counts only chat lines that arrive live. Replayed history (joining a
  /// room, reconnecting) does not touch it, so a screen can tell "someone just
  /// said this" from "this was already on the wall when I walked in" — seat
  /// bubbles pop for the first and stay quiet for the second.
  int liveChatSeq = 0;

  /// Resolved avatar for whoever sent a chat line, or null.
  ///
  /// The line itself carries the sender's photo, which is the only source that
  /// covers spectators and people who have since left the room; the rosters we
  /// hold are the fallback for lines that predate that (chat history replayed
  /// on join). Returns an absolute URL, already filtered: the server omits
  /// photos of people this viewer blocked or reported, so anything found here
  /// is safe to show.
  String? chatPhotoUrlFor(String nickname) {
    if (nickname == playerName) return resolvePhotoUrl(myPhotoUrl);
    final fromLine = _chatPhotos[nickname];
    if (fromLine != null) return resolvePhotoUrl(fromLine);
    for (final p in roomPlayers) {
      if (p != null && p.name == nickname && p.photoUrl != null) {
        return resolvePhotoUrl(p.photoUrl);
      }
    }
    for (final p in gameState?.players ?? const []) {
      if (p.name == nickname && p.photoUrl != null) {
        return resolvePhotoUrl(p.photoUrl);
      }
    }
    for (final p in skGameState?.players ?? const []) {
      if (p.name == nickname && p.photoUrl != null) {
        return resolvePhotoUrl(p.photoUrl);
      }
    }
    for (final p in llGameState?.players ?? const []) {
      if (p.name == nickname && p.photoUrl != null) {
        return resolvePhotoUrl(p.photoUrl);
      }
    }
    for (final p in mightyGameState?.players ?? const []) {
      if (p.name == nickname && p.photoUrl != null) {
        return resolvePhotoUrl(p.photoUrl);
      }
    }
    return null;
  }

  /// HTTP(S) base for the profile-photo upload endpoint.
  String get httpBase => _network.httpBase;

  /// Apply a freshly uploaded (or cleared) own avatar URL locally. The server
  /// also broadcasts profile_photo_updated when in a room, but this covers the
  /// lobby case where there's no room to broadcast to.
  void setMyPhotoUrl(String? url) {
    myPhotoUrl = url;
    // The popup prefers this live value but falls back to the fetched profile,
    // so a *cleared* photo would reappear from the stale snapshot.
    _profiles.setPhotoUrl(playerName, url);
    notifyListeners();
  }

  /// Remove my profile photo. The server clears the key (the paid pass stays,
  /// so another photo can be uploaded), deletes the object, and answers with
  /// profile_photo_updated url:null — the same message an upload ends with.
  void deleteProfilePhoto() {
    _network.send({'type': 'delete_profile_photo'});
  }

  // One-time upload token bridge: request_upload_token (WS) -> upload_token /
  // upload_token_error. The HTTP multipart upload authenticates with the token.
  Completer<({String? token, String? error})>? _uploadTokenCompleter;

  /// Ask the server for a short-lived upload token. Resolves with the token, or
  /// an error reason (not_logged_in / storage_unavailable / no_active_item /
  /// server_error / timeout). Coalesces concurrent requests.
  Future<({String? token, String? error})> requestUploadToken() {
    final existing = _uploadTokenCompleter;
    if (existing != null && !existing.isCompleted) return existing.future;
    final c = Completer<({String? token, String? error})>();
    _uploadTokenCompleter = c;
    _network.send({'type': 'request_upload_token'});
    Future.delayed(const Duration(seconds: 12), () {
      if (!c.isCompleted) c.complete((token: null, error: 'timeout'));
      // Clear the field so a late upload_token reply can't call complete() on
      // this already-completed completer (StateError).
      if (identical(_uploadTokenCompleter, c)) _uploadTokenCompleter = null;
    });
    return c.future;
  }

  // Report result
  String? reportResultMessage;
  bool? reportResultSuccess;

  // Inquiry
  String? inquiryResultMessage;
  bool? inquiryResultSuccess;

  /// 운영자 우편함. Letters the staff sent to this account, newest first.
  List<Map<String, dynamic>> mailbox = [];
  bool mailboxLoading = false;
  String? mailboxError;

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
  // First-ever notices bootstrap: a brand-new install shouldn't see every
  // pre-existing notice flagged as 'NEW'. The first time we receive a
  // notices_result on a device with no prior read history, mark them all
  // as read. Tracked via SharedPreferences so we only do it once per
  // install, even if the user hasn't read anything yet.
  bool _noticesBootstrapped = false;
  static const String _noticesBootstrappedPrefsKey = 'notices_bootstrapped';

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

  /// Letters still wanting something — unread, or holding a reward nobody has
  /// taken out yet (see [mailNeedsAttention]). Joins the same badge as notices
  /// and inquiry replies: three different things arrive in the same place, and
  /// a player should not have to learn which is which to know something is
  /// waiting.
  int get unreadMailCount =>
      mailbox.where(mailNeedsAttention).length + _unreadMailBeyondPage;

  /// 서버가 센 수와 받아온 목록에서 센 수의 차 — mailUnreadBeyondPage 참고.
  int _unreadMailBeyondPage = 0;

  /// Count of answered inquiries the user hasn't read yet. Drives a persistent
  /// badge so the reply is discoverable — the transient lobby banner alone left
  /// users who didn't know to open 문의내역 with a notification that kept
  /// re-appearing every lobby visit. Same criteria as the banner.
  int get unreadInquiryReplyCount {
    int count = 0;
    for (final item in inquiries) {
      final status = item['status']?.toString() ?? '';
      final adminNote = item['admin_note']?.toString() ?? '';
      final userRead = item['user_read'] == true;
      if (status == 'resolved' && adminNote.isNotEmpty && !userRead) count++;
    }
    return count;
  }

  // Push settings
  bool pushEnabled = true;
  bool pushFriendInviteEnabled = true;
  bool isAdminUser = false;
  bool pushAdminInquiryEnabled = true;
  bool pushAdminReportEnabled = true;
  bool pushAdminPaymentEnabled = true;

  /// Marketing pushes. Opt-in, and not cached in SharedPreferences like the
  /// others: consent is a record the server keeps, and a stale local copy
  /// deciding what to show would be the app disagreeing with what was actually
  /// consented to.
  bool marketingPushEnabled = false;

  /// Whether this account has ever answered the consent question. False means
  /// never asked, which is the only state that raises the popup — someone who
  /// declined must not be asked again on every launch.
  bool marketingAsked = false;

  /// A campaign reward that just landed, for the UI to celebrate and clear.
  PushRewardOutcome? pendingPushReward;

  /// The two-yearly confirmation is overdue for this account
  /// (정보통신망법 §50 ⑧). Decided by the server from the consent date.
  bool marketingConfirmDue = false;

  /// When they originally consented. The confirmation notice has to state it.
  DateTime? marketingConsentAt;

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
  List<Map<String, dynamic>> adminTodayMatches = [];
  bool adminTodayMatchesLoading = false;
  String? adminTodayMatchesError;
  bool? _adminTodayMatchesRanked; // tracks last requested filter
  List<Map<String, dynamic>> adminTodayPayments = [];
  bool adminTodayPaymentsLoading = false;
  String? adminTodayPaymentsError;

  // Daily attendance reward state (7-day streak).
  // Shape: { claimedToday, cycleClaimedDays, todayDay, todayRewardGold,
  //          weekRewards: List<int>, resetAtUtc: ISO, totalClaims }
  Map<String, dynamic>? attendanceState;
  bool attendanceLoading = false;
  String? attendanceError;
  bool attendanceClaiming = false; // true while a claim_attendance is in flight
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
  // Mighty previous-trick viewer (shop item, 7-day duration)
  bool hasMightyPrevTrick = false;

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

  /// Most recent mid-match seat change (human took a bot's seat, or vice
  /// versa), or null when there is nothing to announce. Self-clearing.
  SeatHandoff? seatHandoff;

  // A deploy is moving our match between servers. We reconnected here before
  // the room did, so we're in the lobby; the server pulls us in once it
  // arrives. Derived from being roomless so every path that puts us in a room
  // — pulled in, joined another, created one — clears it for free.
  //
  // The promise can also just not come true: the old server may be killed
  // mid-drain, or the room may die over there. Nothing would tell us, so the
  // banner gets its own expiry rather than sitting on screen forever.
  // 3 minutes, not 1: a smoke test measured a 55s wait for the round in
  // progress on the old server to finish, which would have left the banner
  // expiring five seconds before the match actually arrived.
  static const _matchIncomingTtl = Duration(minutes: 3);
  bool _matchIncoming = false;
  Timer? _matchIncomingTimer;
  bool get matchIncoming => _matchIncoming && currentRoomId.isEmpty;
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
    _subscription = _network.messageStream.listen(_onMessage);
    // No FCM on web, and no Firebase app to ask for one — this used to throw
    // straight out of the constructor, which Provider surfaces as a failure of
    // whatever first read the service (the EULA fetch), leaving a spinner.
    if (!kIsWeb) {
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
    }
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

  /// In a room with no game running — as a player OR as a spectator.
  ///
  /// Both see the same waiting room now: the four bespoke spectator waiting
  /// rooms were the same seats, the same chat and the same room settings drawn
  /// four more times, and they drifted from the real one every time it changed.
  /// [isInWaitingRoom] stays player-only because the things that ask it —
  /// inviting a friend, being invited — are things a spectator cannot do.
  bool get isInRoomWithoutGame => hasRoom && !hasActiveGame;
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
      // Watching a room with nothing being played yet: that is the waiting
      // room, and it is the same waiting room the players are looking at.
      // Only a running match needs the game screens.
      if (!hasActiveGame && !hasSpectatorGameState) {
        return AppDestination.waitingRoom;
      }
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
  List<Color> get themeGradient => themeGradientFor(equippedTheme);

  /// Gradient for any theme key, equipped or not — the shop needs to draw a
  /// theme the player does not own yet.
  List<Color> themeGradientFor(String? themeKey) {
    switch (themeKey) {
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
      // 개척자 테마 — 개척자 배너와 짝을 이루는 색이다. 둘을 같이 걸면
      // 세트로 보이고, 따로 걸어도 어색하지 않을 만큼은 옅게 잡았다.
      //
      // 배너는 어두운 것도 있지만 테마는 전부 밝다. 테마는 앱 전체 배경이라
      // 어두우면 모든 화면의 진한 글자가 죽는다 — 기존 13종이 전부 옅은
      // 이유이기도 하다.
      case 'theme_pio_deep':
        return const [Color(0xFFE6F2F1), Color(0xFFD3E9E6), Color(0xFFE8F4F2)];
      case 'theme_pio_gilt':
        return const [Color(0xFFF2EFEA), Color(0xFFE6DFD2), Color(0xFFEFEAE1)];
      case 'theme_pio_oilslick':
        return const [Color(0xFFEFE9F5), Color(0xFFEDE6E0), Color(0xFFF5EFE2)];
      case 'theme_pio_nebula':
        return const [Color(0xFFEDE7F6), Color(0xFFE3ECF7), Color(0xFFE0F2F6)];
      case 'theme_pio_aurora':
        return const [Color(0xFFE4F3EC), Color(0xFFE6F0F2), Color(0xFFEDE7F6)];
      case 'theme_pio_pearl':
        return const [Color(0xFFF5EDF2), Color(0xFFEAF1F7), Color(0xFFEDF5EF)];
      case 'theme_pio_champagne':
        return const [Color(0xFFFAF3E6), Color(0xFFF3E6CE), Color(0xFFFBF6EC)];
      case 'theme_pio_haze':
        return const [Color(0xFFEAF1F9), Color(0xFFEBE8F7), Color(0xFFF4EEF5)];
      case 'theme_pio_sage':
        return const [Color(0xFFF4F1E9), Color(0xFFE6EDE1), Color(0xFFF0F3EC)];
      case 'theme_pio_dawn':
        return const [Color(0xFFFCEDE4), Color(0xFFFDF4E8), Color(0xFFEDF3F7)];
      default:
        return const [Color(0xFFF8F4F6), Color(0xFFEDE6F0), Color(0xFFE0ECF6)];
    }
  }

  // Card back colors based on equipped theme: [background, border, innerBorder]
  List<Color> get cardBackColors => cardBackColorsFor(equippedTheme);

  /// Card-back colours for any theme key — the shop previews a theme the
  /// player does not own yet.
  List<Color> cardBackColorsFor(String? themeKey) {
    switch (themeKey) {
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
      // 개척자 테마의 카드 뒷면. 배경보다 한 단계 진하게 잡아야
      // 카드가 배경에 묻히지 않는다.
      case 'theme_pio_deep':
        return const [Color(0xFFDCEFEC), Color(0xFFB9D9D4), Color(0xFFCBE5E1)];
      case 'theme_pio_gilt':
        return const [Color(0xFFEDE8DF), Color(0xFFD8CDBA), Color(0xFFE4DCCB)];
      case 'theme_pio_oilslick':
        return const [Color(0xFFE9E1F0), Color(0xFFD5C9DA), Color(0xFFE2D6C4)];
      case 'theme_pio_nebula':
        return const [Color(0xFFE4DAF0), Color(0xFFCBDAEE), Color(0xFFC9E9F0)];
      case 'theme_pio_aurora':
        return const [Color(0xFFD6EDE1), Color(0xFFD2E6EA), Color(0xFFDFD5EE)];
      case 'theme_pio_pearl':
        return const [Color(0xFFEEE1E9), Color(0xFFDAE6F1), Color(0xFFDEEDE2)];
      case 'theme_pio_champagne':
        return const [Color(0xFFF5EBD7), Color(0xFFE7D3AE), Color(0xFFF0E5CE)];
      case 'theme_pio_haze':
        return const [Color(0xFFDDE8F5), Color(0xFFDCD7F0), Color(0xFFEBDFEC)];
      case 'theme_pio_sage':
        return const [Color(0xFFEDE8DA), Color(0xFFD5E2CB), Color(0xFFE2E9D9)];
      case 'theme_pio_dawn':
        return const [Color(0xFFF8E0D0), Color(0xFFF7E9CF), Color(0xFFDDE9F1)];
      default:
        return const [Color(0xFFFFF1F5), Color(0xFFE6DCE8), Color(0xFFEDE2EF)];
    }
  }

  // Listener wrapper: a single malformed server payload (e.g. an unguarded
  // cast inside a model fromJson) must not throw uncaught into the stream zone
  // and silently strand the game state. Catch, log the offending type, drop
  // just that message.
  void _onMessage(Map<String, dynamic> data) {
    try {
      _handleMessage(data);
    } catch (e, st) {
      debugPrint(
        '[GameService] message handler error type=${data['type']}: $e\n$st',
      );
    }
  }

  void _handleMessage(Map<String, dynamic> data) {
    final type = data['type'] as String?;
    if (type == null) return;

    switch (type) {
      case 'login_success':
        // Logging in as someone else: everything this instance is holding was
        // fetched for the previous account. reset() clears it on logout, but
        // this does not depend on logout having run — a leftover profile or
        // gold ledger from another account is the kind of bug a player reports
        // as "I made a new account and my old record is still there".
        _forgetPreviousAccount(data['nickname'] as String? ?? '');
        playerId = data['playerId'] ?? '';
        playerName = data['nickname'] ?? '';
        // Server-issued immutable account-binding token (bindingUuid of the
        // unchanging tc_users.id). Stamped onto every IAP; stable across
        // renames/sessions so cross-session reconciliation never mismatches.
        iapBindingToken = data['bindingToken'] as String?;
        // Start the app-lived IAP listener now that we're authenticated, so
        // any purchase pending from a previous session gets reconciled even
        // without the user opening the shop.
        ensureIapStarted();
        equippedTheme = data['themeKey'] as String?;
        equippedTitle = data['titleKey'] as String?;
        myPhotoUrl = data['photoUrl'] as String?;
        hasTopCardCounter = data['hasTopCardCounter'] == true;
        hasMightyTrumpCounter = data['hasMightyTrumpCounter'] == true;
        hasMightyPrevTrick = data['hasMightyPrevTrick'] == true;
        authProvider = data['authProvider'] as String? ?? 'local';
        isAdminUser = data['isAdmin'] == true;
        pushEnabled = data['pushEnabled'] != false;
        pushFriendInviteEnabled = data['pushFriendInvite'] != false;
        pushAdminInquiryEnabled = data['pushAdminInquiry'] != false;
        pushAdminReportEnabled = data['pushAdminReport'] != false;
        pushAdminPaymentEnabled = data['pushAdminPayment'] != false;
        marketingPushEnabled = data['marketingPushEnabled'] == true;
        marketingAsked = data['marketingAsked'] == true;
        marketingConfirmDue = data['marketingConfirmDue'] == true;
        marketingConsentAt = DateTime.tryParse(
          data['marketingConsentAt']?.toString() ?? '',
        )?.toLocal();
        // A notification tapped before this connection existed — the cold
        // start case — has been waiting for a session to send it under.
        _flushPushRewardClaims();
        cardViewPref = (data['cardViewPref'] as String?) ?? 'ask';
        loginError = null;
        _parseMaintenanceStatus(
          data['maintenanceStatus'] as Map<String, dynamic>?,
        );
        _savePushPrefs();
        // Analytics: standard login event + bind userId so we can slice
        // funnels per player without leaking PII (nickname stays private).
        AnalyticsService.instance.logLogin(authProvider);
        AnalyticsService.instance.setUserId(
          playerId.isNotEmpty ? playerId : null,
        );
        // Async FCM token update - don't block login
        _sendFcmTokenAsync();
        // Prefetch notices so the unread badge is accurate immediately.
        requestNotices();
        // Same for the mailbox: a letter with a reward in it is worth nothing
        // if the badge only appears after the player happens to open settings.
        loadMailbox();
        // Prefetch the visual catalog so banners/titles/themes render with
        // the admin-edited gradient config from the moment slots appear.
        requestVisualCatalog();
        // Prefetch attendance state so the shop icon badge / banner is
        // accurate the moment the user lands on the lobby.
        requestAttendanceState();
        // Replay any verify_iap_purchase / claim_attendance that were queued
        // while the WS was offline. Server requires ws.nickname for these,
        // so it MUST run after login_success — not on raw WS connect.
        _network.flushRetryQueue();
        notifyListeners();
        break;

      case 'upload_token':
        {
          final c = _uploadTokenCompleter;
          _uploadTokenCompleter = null;
          if (c != null && !c.isCompleted) {
            c.complete((token: data['token'] as String?, error: null));
          }
        }
        break;

      case 'upload_token_error':
        {
          final c = _uploadTokenCompleter;
          _uploadTokenCompleter = null;
          if (c != null && !c.isCompleted) {
            c.complete((
              token: null,
              error: data['reason'] as String? ?? 'error',
            ));
          }
        }
        break;

      case 'profile_photo_updated':
        // A player in the room (re)uploaded their avatar. Update our own
        // reference immediately; other players' new photos surface on the next
        // room/game state broadcast (their player.photoUrl is already updated
        // server-side).
        if (data['playerId'] == playerId) {
          myPhotoUrl = data['url'] as String?;
          _profiles.setPhotoUrl(playerName, myPhotoUrl);
        }
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
        pushAdminPaymentEnabled = data['pushAdminPayment'] != false;
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
        roomListReceived = true;
        notifyListeners();
        break;

      case 'match_incoming':
        _matchIncoming = true;
        _matchIncomingTimer?.cancel();
        _matchIncomingTimer = Timer(_matchIncomingTtl, () {
          _matchIncoming = false;
          notifyListeners();
        });
        notifyListeners();
        break;

      // The room we were promised went away without ever migrating — the last
      // players deserted it, or it couldn't be handed over. Nothing is coming,
      // so drop the banner now instead of making them sit out its full TTL.
      case 'match_cancelled':
        if (_matchIncoming) {
          _matchIncoming = false;
          _matchIncomingTimer?.cancel();
          notifyListeners();
        }
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

      // Took over a bot seat in a live match. The game screens are shared
      // between watching and playing and branch on [isSpectator], so flipping
      // the flag is the whole transition — the player-side `game_state` the
      // server sends right after fills in the hand.
      case 'joined_in_progress':
        isSpectator = false;
        spectatorGameState = null;
        pendingCardViewRequests = {};
        approvedCardViews = {};
        incomingCardViewRequests = [];
        cardViewers = [];
        notifyListeners();
        break;

      // Walked out of a live match. The seat is a bot's now and there is
      // nothing to come back to, so tear down room state the way a kick does.
      case 'left_in_progress':
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
        spectatorGameState = null;
        currentGameType = 'tichu';
        roomMaxPlayers = 4;
        roomBlockedSlots = <int>{};
        roomRandomSeating = false;
        roomAllowMidGameJoin = false;
        roomBotSeatCount = 0;
        roomGameInProgress = false;
        roomSkExpansions = const [];
        chatMessages = [];
        errorMessage = data['message'] as String?;
        notifyListeners();
        Future.delayed(const Duration(seconds: 3), () {
          if (_disposed) return;
          errorMessage = null;
          notifyListeners();
        });
        break;

      // Someone else took over a bot seat / handed theirs to a bot. Purely
      // informational — the roster and game state arrive on their own.
      case 'player_joined_in_progress':
      case 'player_left_in_progress':
        _handleSeatHandoff(data);
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
                    // Already filtered server-side for blocks/reports; empty
                    // when they have no photo or the viewer may not see it.
                    'photoUrl': (s['photoUrl'] ?? '').toString(),
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
        // Server only forwards a request when our cardViewPref == 'ask',
        // so we always queue it for the user to decide.
        final spectatorId = data['spectatorId'] as String?;
        final spectatorNickname = data['spectatorNickname'] as String?;
        if (spectatorId != null && spectatorNickname != null) {
          incomingCardViewRequests.removeWhere(
            (r) => r['spectatorId'] == spectatorId,
          );
          incomingCardViewRequests.add({
            'spectatorId': spectatorId,
            'spectatorNickname': spectatorNickname,
          });
        }
        notifyListeners();
        break;

      case 'card_view_pref_result':
        if (data['success'] == true && data['pref'] is String) {
          cardViewPref = data['pref'] as String;
          notifyListeners();
        }
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
        roomRandomSeating = false;
        roomAllowMidGameJoin = false;
        roomBotSeatCount = 0;
        roomGameInProgress = false;
        roomSkExpansions = const [];
        roomSkExpansions = const [];
        chatMessages = [];
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
        roomRandomSeating = false;
        roomAllowMidGameJoin = false;
        roomBotSeatCount = 0;
        roomGameInProgress = false;
        roomSkExpansions = const [];
        roomSkExpansions = const [];
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
                    // Already filtered server-side for blocks/reports; empty
                    // when they have no photo or the viewer may not see it.
                    'photoUrl': (s['photoUrl'] ?? '').toString(),
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
          roomRandomSeating = room['randomSeating'] == true;
          roomAllowMidGameJoin = room['allowMidGameJoin'] == true;
          roomBotSeatCount = room['botSeatCount'] is int
              ? room['botSeatCount'] as int
              : 0;
          final expansionsList = room['skExpansions'];
          roomSkExpansions = expansionsList is List
              ? expansionsList.whereType<String>().toList(growable: false)
              : const [];
          roomTurnTimeLimit = room['turnTimeLimit'] ?? 30;
          roomTargetScore = room['targetScore'] ?? 1000;
          roomGameInProgress = room['gameInProgress'] == true;
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
        // Fire the deferred room_join analytics now that we know gameType /
        // isRanked from the just-applied room_state.
        if (_pendingRoomEntry != null && currentRoomId.isNotEmpty) {
          _pendingRoomEntry = null;
          AnalyticsService.instance.logRoomJoin(
            gameType: currentGameType,
            isRanked: isRankedRoom,
          );
        }
        notifyListeners();
        break;

      case 'game_state':
        if (currentRoomId.isEmpty) break; // Already left
        // A game is running for us, so the promise is settled either way:
        // this is the migrated match we were waiting for, or we committed to
        // a different one (in which case the old match won't claim us — see
        // attachWaitingMembers). Being in a room only HIDES the banner; it has
        // to actually go off here, or it reappears the moment we're back in
        // the lobby.
        if (_matchIncoming) {
          _matchIncoming = false;
          _matchIncomingTimer?.cancel();
        }
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
                      // Already filtered server-side for blocks/reports; empty
                      // when they have no photo or the viewer may not see it.
                      'photoUrl': (s['photoUrl'] ?? '').toString(),
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
            // Track the IMMEDIATELY previous state (was mistakenly set to the
            // already-stale `mightyGameState`, lagging SFX diffing by one tick
            // — my_turn/card sounds compared against two-updates-ago). Matches
            // the SK/Tichu/LL pattern (_prev = next).
            _prevMightyGameState = nextMighty;
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
                      // Already filtered server-side for blocks/reports; empty
                      // when they have no photo or the viewer may not see it.
                      'photoUrl': (s['photoUrl'] ?? '').toString(),
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
                      // Already filtered server-side for blocks/reports; empty
                      // when they have no photo or the viewer may not see it.
                      'photoUrl': (s['photoUrl'] ?? '').toString(),
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
                      // Already filtered server-side for blocks/reports; empty
                      // when they have no photo or the viewer may not see it.
                      'photoUrl': (s['photoUrl'] ?? '').toString(),
                    },
                  )
                  .toList();
            } else {
              spectators = [];
            }
            gameState = GameStateData.fromJson(state);
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
        // The server sends the sender's photo with the line (already filtered
        // for this viewer). Remember it by nickname: a spectator, or anyone who
        // has left, is in no roster we could look them up in.
        final chatSender = (data['sender'] ?? '') as String;
        final chatPhoto = data['photoUrl'] as String?;
        if (chatSender.isNotEmpty) {
          if (chatPhoto != null) {
            _chatPhotos[chatSender] = chatPhoto;
          } else {
            _chatPhotos.remove(chatSender);
          }
        }
        final msg = {
          'sender': data['sender'] ?? '',
          'senderId': data['senderId'] ?? '',
          'message': data['message'] ?? '',
          'timestamp':
              data['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        };
        chatMessages.add(msg);
        liveChatSeq++;
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
        for (final m in messages) {
          final s = (m['sender'] ?? '') as String;
          final photo = m['photoUrl'] as String?;
          if (s.isNotEmpty && photo != null) _chatPhotos[s] = photo;
        }
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

      case 'match_history_page':
        lastMatchHistoryPage = Map<String, dynamic>.from(data);
        notifyListeners();
        break;

      case 'profile_result':
        _profiles.store(data);
        // My own profile carries the privacy setting; someone else's never does
        // (the server strips it), so this can't be overwritten by looking a
        // stranger up.
        if (data['nickname'] == playerName) {
          final p = data['profile'];
          // Assigned, not merged: the server always sends the full set for
          // one's own profile, so a null here means "you don't have one" —
          // keeping the previous value would carry another account's title
          // over after a logout, which is exactly what used to happen.
          if (p is Map) {
            profilePrivateHidePhoto = p['profilePrivateHidePhoto'] == true;
            equippedBanner = p['bannerKey'] as String?;
            equippedTitleName = p['titleName'] as String?;
            myCustomTitleText = p['customTitleText'] as String?;
            myCustomTitleColor = p['customTitleColor'] as String?;
          }
        }
        notifyListeners();
        break;

      case 'feature_toggle_result':
        if (data['success'] == true) {
          // The server recomputes these; adopting its answer keeps the in-game
          // widgets and the inventory switch from disagreeing.
          hasTopCardCounter = data['hasTopCardCounter'] == true;
          hasMightyTrumpCounter = data['hasMightyTrumpCounter'] == true;
          hasMightyPrevTrick = data['hasMightyPrevTrick'] == true;
          requestInventory();
        } else {
          shopActionSuccess = false;
          shopActionMessage = data['message'] as String?;
        }
        notifyListeners();
        break;

      case 'custom_title_result':
        customTitleSuccess = data['success'] == true;
        customTitleMessage = data['message'] as String?;
        if (data['success'] == true) {
          equippedTitle = data['titleKey'] as String?;
          // Saving a custom title equips it, so the preview sources have to
          // learn its name here too — otherwise the banner preview keeps
          // drawing whatever catalog title was worn before.
          equippedTitleName = data['titleName'] as String?;
          myCustomTitleText = data['titleName'] as String?;
          myCustomTitleColor = data['color'] as String?;
          if (playerName.isNotEmpty) requestProfile(playerName);
        }
        // The inventory row shows the current text; refetch so it is not stale.
        requestInventory();
        notifyListeners();
        break;

      case 'profile_private_result':
        if (data['success'] == true) {
          profilePrivateHidePhoto = data['hidePhoto'] == true;
        }
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
      case 'gold_products_result':
        goldProductsLoading = false;
        if (data['success'] == true) {
          final list = data['products'] as List? ?? [];
          goldProducts = list.map((e) => Map<String, dynamic>.from(e)).toList();
        }
        notifyListeners();
        break;
      case 'bank_deposit_info':
        bankDepositInfo = Map<String, dynamic>.from(data);
        notifyListeners();
        break;
      case 'bank_deposit_result':
        final pending = _bankDepositPending;
        _bankDepositPending = null;
        if (pending != null && !pending.isCompleted) {
          pending.complete(Map<String, dynamic>.from(data));
        }
        break;
      case 'iap_purchase_result':
        // Balance is server-authoritative; apply it from any result even if
        // the request already timed out (keeps the displayed gold correct).
        if (data['success'] == true && data['newGold'] != null) {
          gold = data['newGold'];
        }
        // Resolve ONLY the matching request. Unknown/late ids are ignored
        // (the request already timed out and was cleaned up), so a late
        // response can never complete a different purchase's future.
        final rid = data['requestId'] as String?;
        if (rid != null) {
          final c = _iapPending.remove(rid);
          if (c != null && !c.isCompleted) {
            c.complete(Map<String, dynamic>.from(data));
          }
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
      case 'admin_today_matches_result':
        adminTodayMatchesLoading = false;
        if (data['success'] == true) {
          adminTodayMatches = (data['rows'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          adminTodayMatchesError = null;
        } else {
          adminTodayMatchesError =
              data['message'] as String? ?? 'admin_matches_load_failed';
        }
        notifyListeners();
        break;
      case 'attendance_state_result':
        attendanceLoading = false;
        if (data['success'] == true) {
          attendanceState = {
            'claimedToday': data['claimedToday'] == true,
            'cycleClaimedDays':
                (data['cycleClaimedDays'] as num?)?.toInt() ?? 0,
            'todayDay': (data['todayDay'] as num?)?.toInt() ?? 1,
            'todayRewardGold': (data['todayRewardGold'] as num?)?.toInt() ?? 50,
            'weekRewards': (data['weekRewards'] as List? ?? const [])
                .map((e) => (e as num).toInt())
                .toList(),
            'resetAtUtc': data['resetAtUtc'] as String?,
            'totalClaims': (data['totalClaims'] as num?)?.toInt() ?? 0,
          };
          attendanceError = null;
        } else {
          attendanceError =
              data['message'] as String? ?? 'attendance_state_failed';
        }
        notifyListeners();
        break;
      case 'attendance_claim_result':
        attendanceClaiming = false;
        if (data['success'] == true) {
          final st = data['state'] as Map<String, dynamic>?;
          if (st != null) {
            attendanceState = {
              'claimedToday': st['claimedToday'] == true,
              'cycleClaimedDays':
                  (st['cycleClaimedDays'] as num?)?.toInt() ?? 0,
              'todayDay': (st['todayDay'] as num?)?.toInt() ?? 1,
              'todayRewardGold': (st['todayRewardGold'] as num?)?.toInt() ?? 50,
              'weekRewards': (st['weekRewards'] as List? ?? const [])
                  .map((e) => (e as num).toInt())
                  .toList(),
              'resetAtUtc': st['resetAtUtc'] as String?,
              'totalClaims': (st['totalClaims'] as num?)?.toInt() ?? 0,
            };
          } else {
            // Server granted but didn't echo a state object — still mark
            // today claimed so the badge/banner/button hide immediately.
            final newStreak = (data['newStreak'] as num?)?.toInt();
            attendanceState = {
              ...?attendanceState,
              'claimedToday': true,
              if (newStreak != null) 'cycleClaimedDays': newStreak,
              if (newStreak != null) 'todayDay': newStreak,
            };
          }
          // Reflect the new gold balance immediately.
          final newGold = (data['newGold'] as num?)?.toInt();
          if (newGold != null) gold = newGold;
          attendanceError = null;
        } else {
          // Server-confirmed double-claim → sync local UI even if it lagged.
          if (data['reason'] == 'already_claimed' && attendanceState != null) {
            attendanceState = {...attendanceState!, 'claimedToday': true};
          }
          attendanceError =
              data['message'] as String? ??
              data['reason'] as String? ??
              'claim_failed';
        }
        notifyListeners();
        break;
      case 'admin_today_payments_result':
        adminTodayPaymentsLoading = false;
        if (data['success'] == true) {
          adminTodayPayments = (data['rows'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          adminTodayPaymentsError = null;
        } else {
          adminTodayPaymentsError =
              data['message'] as String? ?? 'admin_payments_load_failed';
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
      case 'admin_inquiry_resolve_result':
      case 'admin_report_status_result':
        adminActionSuccess = data['success'] == true;
        adminActionMessage =
            data['message'] as String? ??
            (adminActionSuccess == true
                ? 'admin_action_success'
                : 'admin_action_failed');
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

      case 'visual_catalog_result':
        if (data['success'] == true) {
          final list = data['items'] as List? ?? [];
          final next = <String, ShopVisual>{};
          for (final raw in list) {
            if (raw is! Map) continue;
            final item = Map<String, dynamic>.from(raw);
            final key = item['item_key'] as String?;
            if (key == null || key.isEmpty) continue;
            final visual = ShopVisual.fromItemMap(item);
            if (visual != null) next[key] = visual;
          }
          visualCatalog = next;
          notifyListeners();
        }
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
          // Flip the local feature flag immediately on purchase for ANY
          // duration tier (7d/30d/…) — the server gate is effect_type-based,
          // so a 30d buy enables the same feature as the 7d one.
          final purchasedKey = data['itemKey'] as String?;
          if (data['success'] == true && purchasedKey != null) {
            if (purchasedKey.startsWith('top_card_counter')) {
              hasTopCardCounter = true;
            }
            if (purchasedKey.startsWith('mighty_trump_counter')) {
              hasMightyTrumpCounter = true;
            }
            if (purchasedKey.startsWith('mighty_prev_trick')) {
              hasMightyPrevTrick = true;
            }
          }
        }
        if (type == 'equip_result' && data['success'] == true) {
          if (data['unequipped'] == true) {
            // Clearing a slot: the payload carries no key, so the category is
            // what says which local copy to drop.
            switch (data['category']) {
              case 'theme':
                equippedTheme = null;
                break;
              case 'title':
                equippedTitle = null;
                equippedTitleName = null;
                break;
              case 'banner':
                equippedBanner = null;
                break;
            }
          } else {
            final themeKey = data['themeKey'] as String?;
            if (themeKey != null) {
              equippedTheme = themeKey;
            }
            final titleKey = data['titleKey'] as String?;
            if (titleKey != null) {
              equippedTitle = titleKey;
              equippedTitleName = data['itemName'] as String?;
            }
            final bannerKey = data['bannerKey'] as String?;
            if (bannerKey != null) {
              equippedBanner = bannerKey;
            }
          }
          // Everything else reads the cached profile (shop previews, the popup),
          // so pull a fresh one instead of leaving them on the old cosmetics.
          if (playerName.isNotEmpty) requestProfile(playerName);
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

      // Coupon redemption. The reward matters to two screens (wallet and
      // inventory) and both are refreshed by the server right after this, so
      // all that is kept here is the outcome the dialog reports.
      case 'coupon_result':
        _couponCompleter?.complete(
          CouponOutcome(
            success: data['success'] == true,
            message: data['message'] as String?,
            rewardType: (data['reward'] as Map?)?['type'] as String?,
            rewardGold: (data['reward'] as Map?)?['gold'] as int?,
            rewardDays: _daysUntil((data['reward'] as Map?)?['expiresAt']),
          ),
        );
        _couponCompleter = null;
        break;

      case 'marketing_consent_result':
        // Trust the server's copy over the optimistic local one. If the write
        // failed, the switch has to go back — silently keeping it on is how an
        // account that opted out keeps receiving ads.
        marketingPushEnabled = data['enabled'] == true;
        marketingAsked = true;
        marketingConfirmDue = false;
        notifyListeners();
        break;

      case 'push_reward_result':
        {
          final id = data['campaignId'] as int?;
          // Acknowledged either way: a refusal ("already claimed", "too late")
          // is a final answer, and retrying it forever would re-send on every
          // reconnect.
          if (id != null) _unclaimedCampaigns.remove(id);
          final reward = data['reward'] as Map?;
          // Only a payout is worth interrupting someone for. A tap on an
          // already-claimed notification is not news.
          if (data['success'] == true && reward != null) {
            pendingPushReward = PushRewardOutcome(
              title: data['title'] as String?,
              rewardType: reward['type'] as String?,
              gold: reward['gold'] as int?,
              itemKey: reward['itemKey'] as String?,
              days: reward['days'] as int?,
            );
            notifyListeners();
          }
        }
        break;

      case 'mailbox_result':
        mailboxLoading = false;
        if (data['success'] == true) {
          mailbox =
              (data['mail'] as List?)
                  ?.map((e) => (e as Map).cast<String, dynamic>())
                  .toList() ??
              [];
          // 목록은 최근 50통까지다. 서버가 같이 내려준 정확한 수와의 차이를
          // 들고 있다가 배지에 더한다 — mailUnreadBeyondPage 참고.
          _unreadMailBeyondPage = mailUnreadBeyondPage(
            mailbox.where(mailNeedsAttention).length,
            (data['unread'] as num?)?.toInt(),
          );
          mailboxError = null;
        } else {
          mailboxError = data['message'] as String?;
        }
        notifyListeners();
        break;

      case 'mail_delete_result':
        if (data['success'] != true) {
          // The optimistic removal was wrong (an unclaimed reward, a letter
          // that had already gone). Put the mailbox back the way the server
          // sees it rather than guessing.
          mailboxError = data['message'] as String?;
          loadMailbox();
        }
        notifyListeners();
        break;

      case 'mail_claim_result':
        final claimedId = data['mailId'];
        if (data['success'] == true) {
          // Reflect it locally instead of refetching the whole box: the server
          // has already committed, and a list that visibly lags behind the
          // button reads as the claim not having worked.
          for (final m in mailbox) {
            if (m['id'] == claimedId) {
              m['claimed_at'] = DateTime.now().toUtc().toIso8601String();
              m['read_at'] ??= m['claimed_at'];
            }
          }
          lastMailReward = data['reward'] as Map<String, dynamic>?;
        } else {
          // 실패도 결과다. 화면이 이걸 집어가지 않으면 버튼이 '수령 중'
          // 상태로 굳는다 — 만료·이미 수령·다른 기기에서 먼저 수령처럼
          // 정상적으로 일어나는 실패에서.
          _failedMailClaim = (
            id: claimedId is int ? claimedId : null,
            message: data['message'] as String?,
          );
          mailboxError = data['message'] as String?;
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
          } else if (!_noticesBootstrapped) {
            // First-ever notices_result on this install. If the user has
            // no prior read history, treat them as a new user and hide
            // the 'NEW' badge on every currently-published notice. Users
            // who already read some notices (upgrading from older builds)
            // just get the flag set with no change.
            if (_readNoticeIds.isEmpty) {
              markCurrentNoticesAsRead();
            }
            _noticesBootstrapped = true;
            _saveNoticesBootstrappedFlag();
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
    // NOTE: We intentionally do NOT arm the 2s game-state hold here. The Dog
    // can only be led on an empty trick, so there are no played cards to keep
    // visible — holding the state just froze the turn indicator on the Dog
    // player (the old currentPlayer) for 2s instead of moving it to the
    // partner who now leads. The _buildDogPlayedBanner (driven by its own
    // _dogClearTimer below) already conveys that the Dog was played.

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

  /// Someone at the table changed between human and bot mid-match.
  ///
  /// Kept separate from [desertedPlayerName]: that one means the match is
  /// over, and reusing it here would pop the game-over UI on a game that is
  /// still running. Screens read [seatHandoff] to show a passing banner.
  void _handleSeatHandoff(Map<String, dynamic> data) {
    final joined = data['type'] == 'player_joined_in_progress';
    seatHandoff = SeatHandoff(
      joined: joined,
      playerName: (data['playerName'] as String?) ?? '',
      botName: (data['botName'] as String?) ?? '',
      slot: data['slot'] is int ? data['slot'] as int : -1,
    );
    notifyListeners();
    // The banner is a transient notice, not state the screens have to clear.
    Future.delayed(const Duration(seconds: 4), () {
      if (_disposed) return;
      seatHandoff = null;
      notifyListeners();
    });
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
    final prevDiscardTotal = prev.players.fold<int>(
      0,
      (s, p) => s + p.discardPile.length,
    );
    final nextDiscardTotal = next.players.fold<int>(
      0,
      (s, p) => s + p.discardPile.length,
    );
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

  void _handleMightySfxTransitions(
    MightyGameStateData? prev,
    MightyGameStateData next,
  ) {
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
      if (next.phase == 'trick_end') {
        // The trick-completing (last) card doesn't grow currentTrick — the
        // server clears it in _resolveTrick and sends phase='trick_end' with an
        // empty currentTrick — so the "trick grew" check above misses it. Play
        // the card sound here so the final card of each trick isn't silent.
        _sfx.play('card');
      } else if (next.phase == 'round_end') {
        _sfx.play('round_end');
      } else if (next.phase == 'game_end') {
        // Check if self won (highest score)
        final self = next.players.where((p) => p.position == 'self');
        if (self.isNotEmpty) {
          final myScore = next.scores[self.first.id] ?? 0;
          final maxScore = next.scores.values.isEmpty
              ? 0
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

  /// Drops everything cached for whoever was logged in before [nickname].
  ///
  /// No-op when it is the same account (a reconnect or a session restore), so
  /// coming back from a dropped connection does not blank the friends list.
  void _forgetPreviousAccount(String nickname) {
    if (playerName.isEmpty || playerName == nickname) return;
    _profiles.clear();
    _chatPhotos.clear();
    goldHistory = [];
    inventoryItems = [];
    inventoryLoading = false;
    shopItems = [];
    shopLoading = false;
    friends = [];
    friendsData = [];
    pendingFriendRequests = [];
    pendingFriendRequestCount = 0;
    sentFriendRequests = {};
    blockedUsers = {};
    dmConversations = [];
    dmMessages = {};
    totalUnreadDmCount = 0;
    searchResults = [];
    roomInvites = [];
    inquiries = [];
    myRank = null;
    myRankData = null;
    attendanceState = null;
    adRewardRemaining = 0;
    gold = 0;
    leaveCount = 0;
    equippedTitleName = null;
    equippedBanner = null;
    myCustomTitleText = null;
    myCustomTitleColor = null;
    profilePrivateHidePhoto = false;
    isAdminUser = false;
  }

  void reset() {
    _dogClearTimer?.cancel();
    _dogClearTimer = null;
    _inquiryBannerTimer?.cancel();
    _inquiryBannerTimer = null;
    _pushToggleTimer?.cancel();
    _pushToggleTimer = null;
    _prevGameState = null;
    _prevSKGameState = null;
    _prevLLGameState = null;
    _pendingRoomEntry = null;
    // Unbind the analytics user id on session reset so the next login binds
    // a fresh playerId.
    AnalyticsService.instance.setUserId(null);
    playerId = '';
    playerName = '';
    _chatPhotos.clear();
    liveChatSeq = 0;
    equippedTheme = null;
    equippedTitle = null;
    equippedTitleName = null;
    equippedBanner = null;
    myPhotoUrl = null;
    myCustomTitleText = null;
    myCustomTitleColor = null;
    customTitleMessage = null;
    customTitleSuccess = null;
    profilePrivateHidePhoto = false;
    attendanceState = null;
    attendanceLoading = false;
    attendanceError = null;
    attendanceClaiming = false;
    adRewardRemaining = 0;
    iapBindingToken = null;
    currentRoomId = '';
    currentRoomName = '';
    roomPlayers = List.filled(4, null);
    isHost = false;
    isRankedRoom = false;
    roomTurnTimeLimit = 30;
    roomTargetScore = 1000;
    roomMaxPlayers = 4;
    roomBlockedSlots = <int>{};
    roomRandomSeating = false;
    roomAllowMidGameJoin = false;
    roomBotSeatCount = 0;
    roomGameInProgress = false;
    roomSkExpansions = const [];
    currentGameType = 'tichu';
    roomList = [];
    roomListReceived = false;
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
    llGameState = null;
    mightyGameState = null;
    _prevMightyGameState = null;
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
    pushAdminPaymentEnabled = true;
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
    hasMightyPrevTrick = false;
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
    llGameState = null;
    mightyGameState = null;
    spectatorGameState = null;
    _prevGameState = null;
    _prevSKGameState = null;
    _prevLLGameState = null;
    _prevMightyGameState = null;
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

  void setAdminAlertPush({bool? inquiry, bool? report, bool? payment}) {
    final payload = <String, dynamic>{'type': 'update_push_setting'};
    if (inquiry != null) {
      pushAdminInquiryEnabled = inquiry;
      payload['inquiryAlert'] = inquiry;
    }
    if (report != null) {
      pushAdminReportEnabled = report;
      payload['reportAlert'] = report;
    }
    if (payment != null) {
      pushAdminPaymentEnabled = payment;
      payload['paymentAlert'] = payment;
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

  void requestAdminTodayMatches({bool? ranked, int limit = 100}) {
    // Reuse cached data when filter unchanged.
    if (_adminTodayMatchesRanked == ranked && adminTodayMatches.isNotEmpty)
      return;
    _adminTodayMatchesRanked = ranked;
    adminTodayMatchesLoading = true;
    adminTodayMatchesError = null;
    adminTodayMatches = const [];
    notifyListeners();
    _network.send({
      'type': 'get_admin_today_matches',
      'ranked': ?ranked,
      'limit': limit,
    });
  }

  void requestAdminTodayPayments({int limit = 100}) {
    adminTodayPaymentsLoading = true;
    adminTodayPaymentsError = null;
    adminTodayPayments = const [];
    notifyListeners();
    _network.send({'type': 'get_admin_today_payments', 'limit': limit});
  }

  // Daily attendance — pure read, cheap; safe to call on screen open.
  void requestAttendanceState() {
    attendanceLoading = true;
    attendanceError = null;
    notifyListeners();
    _network.send({'type': 'get_attendance_state'});
  }

  // Claim today's reward. The caller (UI) is expected to gate this on a
  // rewarded-ad completion. Server is the source of truth for idempotency
  // (rejects same-day re-claim), so a stray call can't double-grant.
  void claimAttendance() {
    if (attendanceClaiming) return;
    attendanceClaiming = true;
    attendanceError = null;
    notifyListeners();
    _network.send({'type': 'claim_attendance'});
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

  /// Break into a running match by taking over a bot seat. The server picks
  /// which seat — deliberately, so nobody scouts the table from the spectate
  /// view and then claims the winning hand.
  void joinInProgress() {
    _network.send({'type': 'join_in_progress'});
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

  /// Update the persistent card-view policy on the server. Local state
  /// updates only after the server confirms via `card_view_pref_result`.
  void setCardViewPref(String pref) {
    if (pref != 'ask' && pref != 'always_allow' && pref != 'always_deny') {
      return;
    }
    _network.send({'type': 'set_card_view_pref', 'pref': pref});
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
    bool allowSpectators = true,
    bool allowMidGameJoin = false,
  }) {
    final msg = <String, dynamic>{
      'type': 'create_room',
      'roomName': roomName,
      'password': password,
      'isRanked': isRanked,
      'turnTimeLimit': turnTimeLimit,
      'targetScore': targetScore,
      'allowSpectators': allowSpectators,
      'allowMidGameJoin': allowMidGameJoin,
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
    AnalyticsService.instance.logRoomCreate(
      gameType: gameType,
      isRanked: isRanked,
      maxPlayers: maxPlayers,
    );
  }

  void joinRoom(String roomId, {String password = ''}) {
    _network.send({
      'type': 'join_room',
      'roomId': roomId,
      'password': password,
    });
    // Mark that we're expecting to enter a room; the actual analytics log
    // fires when the first room_state arrives with the full room metadata
    // (so invite-token joins, which lack a roomList cache hit, are covered
    // accurately too).
    _pendingRoomEntry = 'join';
  }

  void joinRoomByInviteToken(String token) {
    _network.send({'type': 'join_room_by_invite', 'token': token});
    _pendingRoomEntry = 'invite';
  }

  void leaveRoom() {
    _network.send({'type': 'leave_room'});
    // If we're offline the send is a no-op and the server can't reply with
    // a state change. Clear locally so the user isn't stranded on a stale
    // game screen with no way out.
    if (!_network.isConnected) {
      _clearRoomState();
    }
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
    roomRandomSeating = false;
    roomAllowMidGameJoin = false;
    roomBotSeatCount = 0;
    roomGameInProgress = false;
    roomSkExpansions = const [];
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

  void addBot({
    int? targetSlot,
    String speed = 'normal',
    String strategy = 'heuristic',
  }) {
    final msg = <String, dynamic>{
      'type': 'add_bot',
      'speed': speed,
      'strategy': strategy,
    };
    if (targetSlot != null) msg['targetSlot'] = targetSlot;
    _network.send(msg);
  }

  void blockSlot(int slotIndex) {
    _network.send({'type': 'block_slot', 'slotIndex': slotIndex});
  }

  void unblockSlot(int slotIndex) {
    _network.send({'type': 'unblock_slot', 'slotIndex': slotIndex});
  }

  void setRandomSeating(bool enabled) {
    _network.send({'type': 'set_random_seating', 'enabled': enabled});
  }

  void setMidGameJoin(bool enabled) {
    _network.send({'type': 'set_mid_game_join', 'enabled': enabled});
  }

  void toggleReady() {
    _network.send({'type': 'toggle_ready'});
  }

  void startGame() {
    _network.send({'type': 'start_game'});
    AnalyticsService.instance.logGameStart(
      gameType: currentGameType,
      isRanked: isRankedRoom,
      playerCount: playerCount,
    );
  }

  // SK actions
  void loadMailbox() {
    mailboxLoading = true;
    mailboxError = null;
    notifyListeners();
    _network.send({'type': 'get_mailbox'});
  }

  /// Mark a letter read. Applied locally first — the badge has to drop the
  /// moment the letter opens, not a round trip later.
  void markMailRead(int mailId) {
    for (final m in mailbox) {
      if (m['id'] == mailId && m['read_at'] == null) {
        m['read_at'] = DateTime.now().toUtc().toIso8601String();
      }
    }
    notifyListeners();
    _network.send({'type': 'read_mail', 'mailId': mailId});
  }

  void claimMail(int mailId) {
    _network.send({'type': 'claim_mail', 'mailId': mailId});
  }

  /// Throw a letter away. Removed locally first — the row is gone server-side
  /// by the time the reply lands, and a list that keeps showing what you just
  /// deleted reads as the button not working.
  void deleteMail(int mailId) {
    mailbox.removeWhere((m) => m['id'] == mailId);
    notifyListeners();
    _network.send({'type': 'delete_mail', 'mailId': mailId});
  }

  /// 실패한 수령. 성공한 보상과 같은 방식으로 화면이 한 번 집어간다 —
  /// 화면은 이걸 받아야 '수령 중' 표시를 풀 수 있다.
  ({int? id, String? message})? _failedMailClaim;

  ({int? id, String? message})? takeFailedMailClaim() {
    final f = _failedMailClaim;
    _failedMailClaim = null;
    return f;
  }

  /// The reward from the most recent successful claim, for the screen to show
  /// once. Cleared by the reader.
  Map<String, dynamic>? lastMailReward;
  Map<String, dynamic>? takeMailReward() {
    final r = lastMailReward;
    lastMailReward = null;
    return r;
  }

  /// Tell the server a notification was opened. Statistics only — there is no
  /// reply and nothing depends on it arriving.
  void reportPushOpened(String kind, int pushId) {
    _network.send({'type': 'push_opened', 'kind': kind, 'pushId': pushId});
  }

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
    _network.send({'type': 'submit_bid', 'points': points, 'suit': suit});
  }

  void mightyPass() {
    _network.send({'type': 'submit_bid', 'pass': true});
  }

  void mightyDeclareDealMiss() {
    _network.send({'type': 'declare_deal_miss'});
  }

  void mightyDeclareSetting() {
    _network.send({'type': 'declare_setting'});
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

  void mightyPlayCard(
    String cardId, {
    String? jokerSuit,
    bool jokerCall = false,
  }) {
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

  /// How far the profile-privacy pass reaches: records only (false) or the
  /// profile photo as well (true). Mirrors the server's stored preference so the
  /// switch can render before the next profile fetch lands.
  bool profilePrivateHidePhoto = false;

  void setProfilePrivateHidePhoto(bool hide) {
    profilePrivateHidePhoto = hide;
    notifyListeners();
    _network.send({'type': 'set_profile_private_photo', 'hide': hide});
  }

  // Request user profile
  Completer<CouponOutcome>? _couponCompleter;

  /// How many whole days until [iso], or null when there is no expiry.
  static int? _daysUntil(dynamic iso) {
    if (iso == null) return null;
    final at = DateTime.tryParse(iso.toString());
    if (at == null) return null;
    final days = at.difference(DateTime.now()).inHours / 24;
    return days <= 0 ? 0 : days.round();
  }

  /// Redeem a coupon code and wait for the server's verdict.
  ///
  /// Only one at a time: the reply carries no request id, so a second attempt
  /// in flight would have its answer handed to the first waiter. The UI
  /// disables the button while this is pending, and this makes that a rule
  /// rather than a hope.
  Future<CouponOutcome> redeemCoupon(String code) {
    final existing = _couponCompleter;
    if (existing != null) return existing.future;
    final completer = Completer<CouponOutcome>();
    _couponCompleter = completer;
    _network.send({'type': 'redeem_coupon', 'code': code});
    Future.delayed(const Duration(seconds: 12), () {
      if (identical(_couponCompleter, completer) && !completer.isCompleted) {
        _couponCompleter = null;
        completer.complete(const CouponOutcome(success: false));
      }
    });
    return completer.future;
  }

  void requestProfile(String nickname) {
    _profiles.beginRequest(nickname);
    _network.send({'type': 'get_profile', 'nickname': nickname});
  }

  /// The last page of match history the server sent, for whoever asked.
  ///
  /// The full-history list is the only thing that reads it, and it only ever
  /// has one open at a time, so a single slot beats a cache keyed by request.
  /// Consumers check the nickname and offset before taking it — a page for a
  /// different profile is one that arrived late.
  Map<String, dynamic>? lastMatchHistoryPage;

  /// Ask for `limit` matches starting at `offset`.
  ///
  /// [gameType] is the tab being read, or `'all'`. The server pages one tab at
  /// a time on purpose: the profile popup's own list is capped per game so no
  /// tab starves, which is the opposite of what a paged list needs.
  void requestMatchHistory(
    String nickname, {
    required String gameType,
    required int offset,
    int limit = 20,
  }) {
    _network.send({
      'type': 'get_match_history',
      'nickname': nickname,
      'gameType': gameType,
      'offset': offset,
      'limit': limit,
    });
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
    skGameState = null;
    llGameState = null;
    mightyGameState = null;
    _prevGameState = null;
    _prevSKGameState = null;
    _prevLLGameState = null;
    _prevMightyGameState = null;
    errorMessage = 'room_restore_fallback';
    notifyListeners();
    Future.delayed(const Duration(seconds: 3), () {
      if (_disposed) return;
      if (errorMessage == 'room_restore_fallback') {
        errorMessage = null;
        notifyListeners();
      }
    });
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

  // Shop / EULA. `locale` is optional — pass the device/user locale so the
  // server returns the right-language EULA/privacy on first launch (before
  // login, ws.locale is still null).
  void requestAppConfig({String? locale}) {
    final msg = <String, dynamic>{'type': 'get_app_config'};
    if (locale != null) msg['locale'] = locale;
    _network.send(msg);
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

  // Web has no store purchase path at all (server.js:7981 routes only to
  // Apple/Google), so this is never sent from a browser.
  String get _iapPlatform =>
      kIsWeb ? 'web' : (Platform.isIOS ? 'ios' : 'android');

  void requestGoldProducts() {
    goldProductsLoading = true;
    notifyListeners();
    _network.send({'type': 'get_gold_products', 'platform': _iapPlatform});
  }

  // Bank transfer (web only). Asking on a mobile build would be harmless —
  // the server would answer — but the shop never calls this off the web, and
  // the account details must not reach a store build.
  void requestBankDepositInfo() {
    if (!kIsWeb) return;
    _network.send({'type': 'get_bank_deposit_info'});
  }

  Completer<Map<String, dynamic>>? _bankDepositPending;

  // Tells the server the player says they've transferred the money, which
  // notifies the admins. Grants nothing by itself — an admin confirms the
  // deposit by hand and issues the gold.
  Future<Map<String, dynamic>> requestBankDeposit(
    String productId,
    String depositor,
  ) {
    // The button is disabled while one is in flight, but a reconnect could
    // still strand the old completer; hand the caller the live one rather
    // than leaking a future nobody completes.
    final existing = _bankDepositPending;
    if (existing != null && !existing.isCompleted) return existing.future;

    final completer = Completer<Map<String, dynamic>>();
    _bankDepositPending = completer;
    _network.send({
      'type': 'request_bank_deposit',
      'productId': productId,
      'depositor': depositor,
    });
    // A dropped socket must not leave the dialog spinning forever.
    Future.delayed(const Duration(seconds: 15), () {
      if (!completer.isCompleted) {
        completer.complete({'success': false, 'timeout': true});
        if (identical(_bankDepositPending, completer)) {
          _bankDepositPending = null;
        }
      }
    });
    return completer.future;
  }

  // Correlated pending verifications keyed by a per-request id echoed by the
  // server. A single completer is NOT safe: after a 20s local timeout the
  // server may still respond late, and without correlation that late response
  // would resolve the NEXT purchase's completer (cross-wiring finish/toasts).
  final Map<String, Completer<Map<String, dynamic>>> _iapPending = {};
  int _iapReqSeq = 0;

  // Sends the store verification payload and resolves with the server's
  // verdict for THIS request only (matched by requestId). Self-times-out and
  // cleans up its map entry so a late response can never complete another
  // request.
  Future<Map<String, dynamic>> verifyIapPurchase({
    required String productId,
    required String verificationData,
    String? transactionId,
  }) {
    final reqId = '${DateTime.now().microsecondsSinceEpoch}_${_iapReqSeq++}';
    final completer = Completer<Map<String, dynamic>>();
    _iapPending[reqId] = completer;
    _network.send({
      'type': 'verify_iap_purchase',
      'requestId': reqId,
      'platform': _iapPlatform,
      'productId': productId,
      'verificationData': verificationData,
      if (transactionId != null && transactionId.isNotEmpty)
        'transactionId': transactionId,
    });
    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        _iapPending.remove(reqId);
        return {'success': false, 'message': 'timeout'};
      },
    );
  }

  // App-lived IAP service. Created once and kept listening for the whole
  // session so a purchase left pending after a transient verify failure is
  // reconciled on the next launch even if the user never reopens the shop.
  IapService? _iap;
  IapService? get iap => _iap;

  /// Server-issued immutable account-binding token (from login_success).
  String? iapBindingToken;

  void ensureIapStarted() {
    if (_iap != null) return;
    final svc = IapService(
      verify: verifyIapPurchase,
      bindingTokenProvider: () => iapBindingToken,
    );
    _iap = svc;
    // Fire-and-forget; init() is idempotent and safe if the store is absent.
    svc.init();
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

  /// Fetch the visual catalog (banners/titles/themes visual config from
  /// tc_shop_items.metadata.visual). Cached in [visualCatalog] for the
  /// lifetime of the login session.
  void requestVisualCatalog() {
    _network.send({'type': 'get_visual_catalog'});
  }

  /// Lookup the banner-style gradient for an item key. Returns null when the
  /// catalog hasn't been loaded yet or the key isn't registered.
  LinearGradient? bannerGradient(String? itemKey) {
    if (itemKey == null) return null;
    return visualCatalog[itemKey]?.previewGradient();
  }

  /// Server-provided override text color for the banner (admin-editable via
  /// metadata.visual.text.color). Returns null when not set — caller should
  /// fall back to its own default text color.
  Color? bannerTextColor(String? itemKey) {
    if (itemKey == null) return null;
    return visualCatalog[itemKey]?.textColor;
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

  /// Result of the last custom-title save: null while none is pending, then the
  /// server's message (success or the reason it refused).
  String? customTitleMessage;
  bool? customTitleSuccess;

  /// My own custom title, as last saved. The profile payload also carries it,
  /// but a fetch has to come back first — and the editor is usually reopened
  /// before that, which is how it kept seeding the previous title.
  String? myCustomTitleText;
  String? myCustomTitleColor;

  /// Switch a feature pass on or off. The days keep running either way.
  void setFeatureEnabled(String effectType, bool enabled) {
    _network.send({
      'type': 'set_feature_enabled',
      'effectType': effectType,
      'enabled': enabled,
    });
  }

  void setCustomTitle(String text, String colorId) {
    _network.send({'type': 'set_custom_title', 'text': text, 'color': colorId});
  }

  /// Take off whatever is equipped in this category (banner / title / theme).
  void unequipCategory(String category) {
    _network.send({'type': 'unequip_item', 'category': category});
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
    _chatPhotos.clear();
    liveChatSeq = 0;
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
  /// [reasonCode] tells the server WHAT was reported ('photo', 'title',
  /// 'abuse', 'spam', …). The visible reason is localized text; the server
  /// decides what to hide from this reporter, and it cannot do that by matching
  /// Korean strings.
  void reportUserAction(String nickname, String reason, {String? reasonCode}) {
    _network.send({
      'type': 'report_user',
      'nickname': nickname,
      'reason': reason,
      if (reasonCode != null) 'reasonCode': reasonCode,
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
      _noticesBootstrapped =
          prefs.getBool(_noticesBootstrappedPrefsKey) ?? false;
      if (_disposed) return;
      notifyListeners();
    } catch (_) {
      // Best-effort; ignore prefs errors.
    }
  }

  Future<void> _saveNoticesBootstrappedFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_noticesBootstrappedPrefsKey, true);
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

  /// Mark a single notice as read and persist. No-op if already read.
  void markNoticeRead(int noticeId) {
    if (_readNoticeIds.add(noticeId)) {
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
    // Push has no web implementation; `Platform` below would throw there too.
    if (kIsWeb) return;
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

  /// Answer the marketing consent question — from the first-run popup or from
  /// settings. [marketingAsked] flips either way: declining is an answer, and
  /// re-asking someone who said no is the thing the popup must never do.
  void setMarketingConsent(bool enabled) {
    marketingPushEnabled = enabled;
    marketingAsked = true;
    if (playerId.isNotEmpty) {
      _network.send({'type': 'set_marketing_consent', 'enabled': enabled});
    }
    notifyListeners();
  }

  /// Answer the two-yearly confirmation: keep the subscription, or end it.
  ///
  /// Not the same call as [setMarketingConsent] even when the answer is yes —
  /// this one records that the notice was given, which is the obligation.
  void confirmMarketingConsent(bool keep) {
    marketingConfirmDue = false;
    marketingPushEnabled = keep;
    if (playerId.isNotEmpty) {
      _network.send({'type': 'confirm_marketing_consent', 'keep': keep});
    }
    notifyListeners();
  }

  /// Campaign ids tapped but not yet acknowledged by the server.
  ///
  /// A notification can be tapped while the socket is down — on a cold start
  /// the tap is known before the connection exists. Held here and flushed on
  /// login, so the reward is not lost to whichever happened first.
  final Set<int> _unclaimedCampaigns = <int>{};

  /// The player tapped a campaign notification.
  ///
  /// Safe to call more than once for the same campaign: Firebase delivers the
  /// launch message through two different callbacks depending on whether the
  /// app was terminated or merely backgrounded, and the server pays once
  /// regardless.
  void claimPushReward(int campaignId) {
    _unclaimedCampaigns.add(campaignId);
    _flushPushRewardClaims();
  }

  void _flushPushRewardClaims() {
    if (playerId.isEmpty || _unclaimedCampaigns.isEmpty) return;
    for (final id in _unclaimedCampaigns.toList()) {
      _network.send({'type': 'claim_push_reward', 'campaignId': id});
    }
  }

  /// Called once the celebration has been shown, so it is not shown again.
  void consumePushReward() {
    pendingPushReward = null;
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
    // Notify again AFTER flipping user_read so the unread badge clears now
    // (the earlier notify fired while user_read was still false).
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true; // C2: Mark as disposed
    _matchIncomingTimer?.cancel();
    if (_shareInviteLinkCompleter != null &&
        !_shareInviteLinkCompleter!.isCompleted) {
      _shareInviteLinkCompleter!.completeError(
        StateError('GameService disposed'),
      );
    }
    _shareInviteLinkCompleter = null;
    // Resolve any in-flight IAP verifications so their awaiters don't hang
    // until the 25s timeout fires.
    for (final c in _iapPending.values) {
      if (!c.isCompleted) {
        c.complete({'success': false, 'message': 'disposed'});
      }
    }
    _iapPending.clear();
    _subscription?.cancel();
    _fcmTokenSubscription?.cancel();
    _dogClearTimer?.cancel();
    _inquiryBannerTimer?.cancel();
    _pushToggleTimer?.cancel();
    super.dispose();
  }
}

/// What came back from redeeming a coupon.
///
/// A null [message] with `success: false` means the server never answered —
/// the screen says so in its own words rather than showing an empty error.
/// A campaign reward that arrived and has not been shown yet.
///
/// Gold lands silently in the wallet, so without something on screen the
/// player has no way to know the notification they tapped actually paid.
class PushRewardOutcome {
  final String? title;
  final String? rewardType;
  final int? gold;
  final String? itemKey;
  final int? days;

  const PushRewardOutcome({
    this.title,
    this.rewardType,
    this.gold,
    this.itemKey,
    this.days,
  });
}

class CouponOutcome {
  final bool success;
  final String? message;
  final String? rewardType;
  final int? rewardGold;
  final int? rewardDays;

  const CouponOutcome({
    required this.success,
    this.message,
    this.rewardType,
    this.rewardGold,
    this.rewardDays,
  });
}
