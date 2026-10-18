import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../utils/spectator_line.dart';
import '../services/locale_service.dart';
import '../services/session_service.dart';
import '../models/player.dart';
import '../models/room.dart';
import 'missions_screen.dart';
import 'ranking_screen.dart';
import 'rules_screen.dart';
import 'shop_screen.dart';
import 'settings_screen.dart';
import 'friends_screen.dart';
import '../widgets/hint_bubble.dart';
import '../widgets/sk_expansion_guide.dart';
import '../widgets/token_cosmetics.dart';
import '../widgets/cartoon_icons.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/level_badge.dart';
import '../widgets/notice_body.dart';
import '../widgets/game_type_icon.dart';
import '../util/image_precache.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/host_crown.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/docked_chat_panel.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/title_chip.dart';
import '../theme/cartoon.dart';
import '../utils/banner_ink.dart';
import '../widgets/gold_history_dialog.dart';
import '../widgets/gold_icon.dart';
import '../services/ad_service.dart';
import '../services/kakao_invite_share_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../widgets/spectator_controls.dart';

/// The rooms to show for [gameType], or all of them when it is null.
///
/// Pulled out of the widget so the rule can be tested on its own. It reads as
/// trivial, and it is — but the version before it was a set of SWITCHED-OFF
/// types, so tapping the chip labelled 티츄 hid Tichu. Inverting this by
/// accident produces a screen that looks like it is working.
List<T> filterRoomsByGame<T>(
  List<T> rooms,
  String? gameType,
  String Function(T) typeOf,
) {
  if (gameType == null) return rooms;
  return rooms.where((r) => typeOf(r) == gameType).toList();
}

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _inRoom = false;
  bool _roomMoreOpen = false;

  // 오늘 미션을 아직 안 골랐으면 미션 탭 위에 "오늘의 미션을 선택하세요!" 말풍선을 한 번 띄운다.
  final LayerLink _missionLink = LayerLink();
  OverlayEntry? _missionHint;
  Timer? _missionHintTimer;
  DateTime? _missionsRequestedAt;

  /// 이미 안내를 보여 준 "계정@날" — 날은 미션 상태의 다음 리셋 시각.
  ///
  /// static 인 것은 의도다. 로비를 떠나면 이 State 가 사라지므로, 인스턴스
  /// 필드에 두면 로비를 오갈 때마다 다시 뜬다.
  ///
  /// 계정을 키에 넣는 이유: 리셋 시각은 전역 KST 라 날짜만으로는 같은 기기의
  /// 두 계정이 같은 키를 쓴다. 그러면 A 로 안내를 본 날 B 로 바꿔 들어온
  /// 사람은 그날 안내를 아예 못 본다.
  static String? _missionHintShownFor;

  /// Which game's rooms are showing, or null for all of them.
  ///
  /// Was a set of switched-OFF types, which meant tapping 티츄 hid Tichu —
  /// the opposite of what a coloured chip labelled with a game reads as, and
  /// it took three taps to see one game. Now the chips pick one, the way a tab
  /// bar does, with an explicit 전체 to come back to.
  ///
  /// Deliberately not persisted. A filter left on from last week is invisible
  /// on launch and turns a lobby with rooms in it into "방이 없어요".
  String? _roomGameFilter;

  // 채팅
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

  /// Waiting-room chat, while it is floating: whether the panel is up.
  /// Meaningless while docked — a docked chat is always there.
  bool _roomChatOpen = false;
  int _roomChatRead = 0;

  /// Docked (a strip under the start/ready button) or floating (the same
  /// draggable panel the game screens use). Docked by default: a waiting room
  /// has nothing underneath worth hiding, and the floating panel was a chat
  /// you had to open before you knew there was anything to read.
  ///
  /// Persisted, because it is a preference rather than a per-room choice.
  bool _roomChatDocked = true;
  static const String _kRoomChatDocked = 'room_chat_docked';

  /// Last-resort floor for the docked chat: below this it is a title bar and
  /// a text field with nothing between them, which reads as broken.
  ///
  /// Deliberately small, because whatever the chat reserves comes out of the
  /// seats. A generous floor looked like the safe choice and was not: at 260
  /// a six-seat Skull King room went into a scroller on a phone even though
  /// its seats (~510dp) fit in the ~700dp available with ~190dp to spare.
  /// Waiting for a room you can only see half of is worse than a shortish
  /// chat, so the seats are served first and the chat takes the rest.
  static const double _dockedChatMinHeight = 140;

  /// The floor once the keyboard is fully up. The seats are not what you are
  /// looking at mid-sentence, so here the chat does push into them.
  static const double _dockedChatMinHeightTyping = 240;

  /// Keyboard travel over which the floor moves between the two values.
  /// Shorter than any real keyboard, so the floor has settled before the
  /// keyboard finishes and nothing is still moving at the end of the slide.
  static const double _dockedChatFloorRamp = 180;

  /// The floor right now, blended by how far the keyboard is out.
  ///
  /// Blended rather than switched: `keyboard > 0 ? typing : normal` changes by
  /// 100dp in the single frame the inset reaches zero, and since the floor is
  /// what the seats are measured against, that frame moved the chat and the
  /// seats at once — the visible hitch at the end of the keyboard sliding
  /// away. Ramping it against the inset makes the last frame of the slide
  /// look like every other one.
  ///
  /// The keyboard height has to come off the window rather than off
  /// MediaQuery: the Scaffold resizes its body for the inset and strips it
  /// from the body's MediaQuery, so down here it always reads zero. Same
  /// reason DraggableChatPanel asks View.of — see its _keyboardInset.
  double _dockedChatMinHeightNow() {
    final view = View.of(context);
    final ratio = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    final keyboard = math.max(
      MediaQuery.of(context).viewInsets.bottom,
      view.viewInsets.bottom / ratio,
    );
    // Returned unbounded on purpose — this is a wish, not a verdict. The seat
    // floor can only be honoured against the box the two actually share, and
    // that is known in the LayoutBuilder, not here.
    final base = math.max(_dockedChatMinHeight, _dockedChatHeight ?? 0);
    if (keyboard <= 0) return base;
    final t = (keyboard / _dockedChatFloorRamp).clamp(0.0, 1.0);
    return math.max(
      base,
      _dockedChatMinHeight +
          (_dockedChatMinHeightTyping - _dockedChatMinHeight) * t,
    );
  }

  /// Height the user dragged the docked chat to, if they ever have.
  ///
  /// Held as a floor rather than as the height: the chat already fills
  /// whatever the seats leave, and pinning it to an exact value would open a
  /// gap under the start button whenever that leftover was the larger of the
  /// two. So dragging up takes space from the seats, dragging down gives it
  /// back, and letting go all the way at the bottom lands back on the
  /// automatic behaviour rather than on a stuck small panel.
  double? _dockedChatHeight;
  static const String _kRoomChatHeight = 'room_chat_height';

  /// The chat may never take the seats below this. Enforced where the shared
  /// box is actually known — see _buildRoomBody. Below it there is no room to
  /// see who is in the room at all, which is the one thing a waiting room is
  /// for.
  static const double _dockedChatSeatMinHeight = 130;

  /// Title bar plus input row, and nothing else. The chat is never drawn
  /// shorter than the parts it cannot fold away; below this its own Column
  /// overflows the box. Only reachable on a body too short for the seat
  /// minimum as well — see _buildRoomBody.
  static const double _dockedChatHardMinHeight = 96;

  void _setDockedChatHeight(double height) {
    // A coarse bound on what gets stored, so the number stays sane across
    // devices. It is NOT the seat guarantee: the screen is taller than the box
    // the seats and the chat share (header, safe areas, banner ad all come off
    // first), so clamping here would promise the seats 130dp and deliver less.
    // _buildRoomBody clamps against the real constraints.
    final screen = MediaQuery.of(context).size.height;
    final next =
        height.clamp(
              _dockedChatMinHeight,
              math.max(_dockedChatMinHeight, screen - _dockedChatSeatMinHeight),
            )
            as double;
    if (next == _dockedChatHeight) return;
    setState(() => _dockedChatHeight = next);
  }

  void _saveDockedChatHeight() {
    final height = _dockedChatHeight;
    if (height == null) return;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setDouble(_kRoomChatHeight, height),
    );
  }

  /// The last thing each player said, shown briefly over their seat so a
  /// message is visible without opening the panel at all.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  // 배너 광고 (대기방 전용 — 로비 목록 화면에는 배너를 달지 않는다)
  BannerAd? _roomBannerAd;
  bool _roomBannerLoaded = false;

  // 문의 답변 자동 팝업: 접속(로그인) 후 문의 목록이 로드됐을 때 미읽음 답변이
  // 있으면 답변 팝업을 1회 띄운다. 푸시를 누르고 들어온 경우든 일반 실행이든
  // 답변을 바로 보게 하고, 팝업을 닫으면 읽음처리되어 다시 뜨지 않는다.
  GameService? _inquiryGameRef;
  bool _inquiryReplyShown = false;

  @override
  void initState() {
    super.initState();
    // Bot faces, fetched now rather than when a waiting room first draws one.
    // Needs a context, so it waits for the first frame. See image_precache.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) precacheCommonImages(context);
    });
    // AdMob has no web implementation at all, so this can only fail there.
    // Leaving it to fail was working — the load callbacks null the banner
    // out — but it is a plugin exception per screen to get to the same
    // place. Web ads would be AdSense / H5 Games Ads, a separate product.
    _roomBannerAd = kIsWeb
        ? null
        : AdService.createBannerAd(
            AdService.skWaitingBannerId,
            onAdLoaded: (_) {
              if (mounted) setState(() => _roomBannerLoaded = true);
            },
            onAdFailedToLoad: (ad, error) {
              ad.dispose();
              if (mounted) {
                setState(() {
                  _roomBannerAd = null;
                  _roomBannerLoaded = false;
                });
              }
            },
          );
    _roomBannerAd?.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final game = context.read<GameService>();
      game.requestRoomList();
      game.requestSpectatableRooms();
      game.requestBlockedUsers();
      game.requestFriends();
      game.requestPendingFriendRequests();
      game.requestInquiries();
      game.loadMailbox();
      // Auto-show the reply popup once the inquiry list arrives (or already has
      // an unread reply). Listener so it fires when requestInquiries resolves.
      _inquiryGameRef = game;
      game.addListener(_onInquiryUpdate);
      _onInquiryUpdate();
    });
    _loadRoomChatPrefs();
  }

  /// Resolves long before anyone reaches a waiting room (this screen is built
  /// right after login), so the docked default never visibly flips.
  Future<void> _loadRoomChatPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final docked = prefs.getBool(_kRoomChatDocked);
    final height = prefs.getDouble(_kRoomChatHeight);
    if (!mounted) return;
    if (docked == null && height == null) return;
    setState(() {
      if (docked != null) _roomChatDocked = docked;
      if (height != null) _dockedChatHeight = height;
    });
  }

  void _setRoomChatDocked(bool docked, GameService game) {
    setState(() {
      _roomChatDocked = docked;
      // Popping out lands open rather than hidden — the tap that undocked it
      // was a request to see the chat, not to dismiss it. Docking closes the
      // floating panel so the two don't both show at once.
      _roomChatOpen = !docked;
      if (docked) _roomChatRead = game.chatMessages.length;
    });
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool(_kRoomChatDocked, docked),
    );
    _scrollChatToBottom();
  }

  @override
  void dispose() {
    _hideMissionHint();
    _inquiryGameRef?.removeListener(_onInquiryUpdate);
    _seatChat.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _roomBannerAd?.dispose();
    super.dispose();
  }

  // Show the inquiry reply popup once, the moment an unread answered inquiry is
  // present. Removes its own listener after firing so it shows at most once per
  // lobby mount; closing the popup marks replies read (clears banner + badge).
  void _onInquiryUpdate() {
    if (!mounted || _inquiryReplyShown) return;
    final game = _inquiryGameRef;
    if (game == null) return;
    // Only on the lobby list — never over a waiting room or in-progress game.
    // Check AUTHORITATIVE server state (hasRoom / destination), not just the
    // local _inRoom flag, which flips to false optimistically on leave before
    // the server confirms the exit. Defer WITHOUT consuming: the listener stays
    // active and fires again on the server-confirm notify, once truly on lobby.
    if (_inRoom ||
        game.hasRoom ||
        game.currentDestination != AppDestination.lobby) {
      return;
    }
    Map<String, dynamic>? reply;
    for (final it in game.inquiries) {
      final status = it['status']?.toString() ?? '';
      final adminNote = it['admin_note']?.toString() ?? '';
      if (status == 'resolved' &&
          adminNote.isNotEmpty &&
          it['user_read'] != true) {
        reply = it;
        break;
      }
    }
    if (reply == null) return;
    _inquiryReplyShown = true;
    game.removeListener(_onInquiryUpdate);
    _showInquiryReplyPopup(reply, game);
  }

  void _showInquiryReplyPopup(Map<String, dynamic> item, GameService game) {
    if (!mounted) return;
    final l10n = L10n.of(context);
    final title = item['title']?.toString() ?? '';
    final adminNote = item['admin_note']?.toString() ?? '';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.mark_email_read,
              color: Cartoon.onSurface(const Color(0xFF1E88E5)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.serviceInquiryReply(
                  title.isEmpty ? l10n.serviceInquiryDefault : title,
                ),
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.inquiryAnswerLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Cartoon.onSurface(const Color(0xFF4CAF50)),
                ),
              ),
              const SizedBox(height: 6),
              // The answer is written in markdown by the admin; a plain Text
              // showed the asterisks and ran every paragraph together.
              NoticeBody(content: adminNote),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) game.markInquiriesRead();
    });
  }

  /// 팝업 제목: 색 칩 + 제목 글자. 팝업마다 같은 머리를 쓴다.
  Widget _dialogTitle(IconData icon, Color color, String text) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Cartoon.tint(color, 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Cartoon.ink, size: 22),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            text,
            style: Cartoon.text(size: 20),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 팝업 아래 주 버튼(작은 카툰 버튼).
  Widget _dialogPrimary(
    String label,
    VoidCallback? onPressed, {
    Color color = Cartoon.orange,
  }) {
    return CartoonButton(
      expand: false,
      height: 44,
      color: color,
      onPressed: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: CartoonButton.label(label, size: 17),
      ),
    );
  }

  void _showRoomInviteDialog(Map<String, dynamic> invite, GameService game) {
    final fromNickname = invite['fromNickname'] as String? ?? '';
    final roomName = invite['roomName'] as String? ?? '';
    final isRanked = invite['isRanked'] == true;
    final l10n = L10n.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        title: _dialogTitle(
          Icons.mail_rounded,
          Cartoon.blue,
          l10n.lobbyRoomInviteTitle,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.lobbyRoomInviteMessage(fromNickname),
              style: Cartoon.userText(size: 16),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Cartoon.cream,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  if (isRanked) ...[
                    RankedIcon(width: 18, height: 15),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(roomName, style: Cartoon.userText(size: 16)),
                  ),
                ],
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.lobbyDecline),
          ),
          _dialogPrimary(l10n.lobbyJoin, () {
            Navigator.pop(ctx);
            game.acceptInvite(invite);
            setState(() => _inRoom = true);
          }, color: Cartoon.green),
        ],
      ),
    );
  }

  void _showInviteFriendsDialog(GameService game) {
    game.requestFriends();
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Consumer<GameService>(
        builder: (ctx, game, _) {
          final onlineFriends = game.friendsData
              .where((f) => f['isOnline'] == true && f['roomId'] == null)
              .toList();
          return AlertDialog(
            title: _dialogTitle(
              Icons.person_add_rounded,
              Cartoon.green,
              l10n.lobbyInviteFriendsTitle,
            ),
            content: onlineFriends.isEmpty
                ? SizedBox(
                    height: 70,
                    child: Center(
                      child: Text(
                        l10n.lobbyNoOnlineFriends,
                        style: Cartoon.text(
                          size: 16,
                          color: Cartoon.ink.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  )
                : SizedBox(
                    width: double.maxFinite,
                    height: 260,
                    child: ListView.separated(
                      itemCount: onlineFriends.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        thickness: 1.5,
                        color: Cartoon.ink.withValues(alpha: 0.12),
                      ),
                      itemBuilder: (context, index) {
                        final friend = onlineFriends[index];
                        final nickname = friend['nickname'] as String? ?? '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Cartoon.green,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  nickname,
                                  overflow: TextOverflow.ellipsis,
                                  style: Cartoon.userText(
                                    size: 16,
                                    color: Cartoon.inkOn(Cartoon.green),
                                  ),
                                ),
                              ),
                              CartoonButton(
                                expand: false,
                                height: 36,
                                radius: 13,
                                onPressed: () {
                                  game.inviteToRoom(nickname);
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(
                                    this.context,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l10n.lobbyInviteSent(nickname),
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  child: CartoonButton.label(
                                    l10n.lobbyInvite,
                                    size: 15,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.commonClose),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Small caps-ish heading that separates the settings dialog into "what the
  /// room is called" and "how it plays" — without it the switch read as an
  /// afterthought glued under the name field.
  Widget _settingsSectionLabel(String text) {
    return Text(
      text,
      style: Cartoon.text(size: 14, color: Cartoon.ink.withValues(alpha: 0.6)),
    );
  }

  void _showRoomSettingsDialog(GameService game) {
    final controller = TextEditingController(text: game.currentRoomName);
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _dialogTitle(
          Icons.tune_rounded,
          Cartoon.orange,
          l10n.lobbyRoomSettingsTitle,
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        // Consumer, not StatefulBuilder: the switch reflects room state that
        // the SERVER owns, and it only changes when the room_state broadcast
        // comes back. A local setState repainted with the old value, so the
        // switch visibly snapped back before flicking across a moment later.
        content: Consumer<GameService>(
          builder: (ctx, gs, _) {
            // Ranked rooms can't hold bots, so there is never a seat to take
            // over and the server refuses the toggle — don't offer it.
            final canOfferMidJoin = !gs.isRankedRoom;
            return SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _settingsSectionLabel(l10n.lobbyRoomName),
                    const SizedBox(height: 6),
                    TextField(
                      controller: controller,
                      maxLength: 20,
                      style: Cartoon.userText(size: 16),
                      decoration: InputDecoration(
                        isDense: true,
                        // The 0/20 counter added a whole line of chrome under a
                        // field nobody is at risk of overrunning.
                        counterText: '',
                        hintText: l10n.lobbyEnterRoomTitle,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                      ),
                    ),
                    if (canOfferMidJoin) ...[
                      const SizedBox(height: 18),
                      _settingsSectionLabel(l10n.lobbyRoomRules),
                      const SizedBox(height: 6),
                      // Applied on the spot rather than on "변경", which only
                      // commits the name. A switch that silently needed a second
                      // button to take effect is the kind of thing you find out
                      // about after the game has already started — so the row
                      // says as much, right where the switch is.
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                        decoration: BoxDecoration(
                          color: gs.roomAllowMidGameJoin
                              ? Cartoon.surface(const Color(0xFFE3F4E8))
                              : Cartoon.cream,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            BotSwapIcon(width: 28, height: 28),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.midJoinCreateOption,
                                    style: Cartoon.text(size: 16),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    l10n.midJoinCreateOptionHint,
                                    style: Cartoon.text(
                                      size: 12.5,
                                      color: Cartoon.ink.withValues(
                                        alpha: 0.65,
                                      ),
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.lobbyAppliesImmediately,
                                    style: Cartoon.text(
                                      size: 12,
                                      color: Cartoon.orangeDeep,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              activeThumbColor: Colors.white,
                              activeTrackColor: Cartoon.green,
                              value: gs.roomAllowMidGameJoin,
                              onChanged: (v) => gs.setMidGameJoin(v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          _dialogPrimary(l10n.lobbyChange, () {
            final name = controller.text.trim();
            if (name.isEmpty) return;
            game.changeRoomName(name);
            Navigator.pop(ctx);
          }),
        ],
      ),
    );
  }

  /// Lobby header button that opens your own profile.
  ///
  /// The same box as _buildIconButton (26px glyph + 9px padding), but the photo
  /// *is* the box rather than a small square floating inside it — a bordered
  /// frame around an already-framed avatar read as two nested boxes. The
  /// fallback keeps the tinted plate and the inset glyph so an empty profile
  /// still matches the neighbouring buttons.
  ///
  /// [_headerButtonBox] is shared with those buttons on purpose: this sits in
  /// the same row, and a profile a few pixels short of its neighbours is the
  /// kind of thing you cannot unsee once noticed.
  Widget _buildMyProfileButton(GameService game, double box) {
    const accent = Color(0xFFFF8A65);
    final r = _headerRadiusFor(box);
    // 다른 하단 탭 아이콘과 같은 틀: 불투명 바탕 + 진한 테두리 + 단색 그림자.
    // (바탕이 반투명이면 단색 그림자가 비쳐 어두워지니 꼭 불투명으로.)
    return CartoonPressable(
      onTap: () => _showUserProfileDialog(game.playerName, game),
      scale: 0.86,
      child: Container(
        width: box,
        height: box,
        decoration: BoxDecoration(
          color: Cartoon.tint(accent, 0.55),
          borderRadius: BorderRadius.circular(r),
          border: Border.all(color: Cartoon.ink, width: 2),
          boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(r - 1),
          child: ProfileAvatar(
            photoUrl: game.resolvePhotoUrl(game.myPhotoUrl),
            size: box - 5,
            borderRadius: 0,
            fallback: Icon(
              Icons.person_rounded,
              color: Cartoon.ink,
              size: _headerGlyphFor(box),
            ),
          ),
        ),
      ),
    );
  }

  /// One size for everything in the lobby header row — the four icon buttons
  /// and the profile photo. They sit shoulder to shoulder, so the numbers have
  /// to come from one place or they drift the next time one of them changes.
  ///
  /// The size is measured, not fixed. Five buttons at a hard 44 fit a normal
  /// phone and nothing else: on a narrow one they wrap onto a second line and
  /// the header grows a row, and on a fold or a browser window there is no
  /// reason for them to keep growing — a 60px store icon is not easier to hit,
  /// it just looks like something went wrong. So the row asks how much space
  /// it actually has and clamps between the two.
  static const double _headerButtonMax = 44;
  static const double _headerButtonMin = 34;
  static const int _headerButtonCount = 6;
  static const double _headerButtonGap = 5;

  /// What the logo is guaranteed, and what it may not exceed. It is the
  /// flexible half of this row: on a small phone it gives way so the buttons
  /// stay on one line, on a wide one it stops growing long before the window
  /// does.
  static const double _headerLogoMinWidth = 60;
  static const double _headerLogoMaxWidth = 132;
  static const double _headerLogoGap = 12;

  /// Glyph and corner as a share of the box, so a shrunk button keeps its
  /// proportions instead of a big icon in a small plate.
  static double _headerGlyphFor(double box) => box * (26 / 44);
  static double _headerRadiusFor(double box) => box * (12 / 44);

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    required double box,
  }) {
    // 44 square (26 glyph + 9 either side). The header keeps its width by
    // giving back what the box padding and the gaps between buttons were
    // using — a tap target that reads as a button beats air around it.
    return CartoonPressable(
      onTap: onTap,
      scale: 0.86,
      child: Container(
        width: box,
        height: box,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Cartoon.tint(color, 0.55),
          borderRadius: BorderRadius.circular(_headerRadiusFor(box)),
          border: Border.all(color: Cartoon.ink, width: 2),
          boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
        ),
        child: Icon(icon, color: Cartoon.ink, size: _headerGlyphFor(box)),
      ),
    );
  }

  /// Suggested room name, e.g. "행운의 카드판".
  ///
  /// Words come from `|`-joined lists in the ARB rather than numbered keys, so
  /// adding one is a string edit instead of a new key in three locale files
  /// plus a codegen run. Each game gets its own pair of lists — Mighty and
  /// Love Letter used to borrow Tichu's, which is why a Love Letter room was
  /// called "무적 티츄방".
  final math.Random _nameRandom = math.Random();

  String _generateRandomRoomName({String gameType = 'tichu', L10n? l10n}) {
    final l = l10n ?? L10n.of(context);
    final (adjectives, nouns) = switch (gameType) {
      'skull_king' => (l.lobbyRandomAdjSk, l.lobbyRandomNounSk),
      'mighty' => (l.lobbyRandomAdjMighty, l.lobbyRandomNounMighty),
      'love_letter' => (l.lobbyRandomAdjLl, l.lobbyRandomNounLl),
      _ => (l.lobbyRandomAdjTichu, l.lobbyRandomNounTichu),
    };
    // Random, not the clock. Both halves used to be derived from
    // millisecondsSinceEpoch — the adjective simply walked forward one step
    // per tap, and the noun barely moved at all, so re-rolling felt broken.
    final adj = adjectives.split('|');
    final noun = nouns.split('|');
    return '${adj[_nameRandom.nextInt(adj.length)]} '
        '${noun[_nameRandom.nextInt(noun.length)]}';
  }

  void _showCreateRoomDialog() {
    final l10n = L10n.of(context);
    String randomName = _generateRandomRoomName(l10n: l10n);
    final controller = TextEditingController();
    final passwordController = TextEditingController();
    bool isPrivate = false;
    bool isRanked = false;
    bool allowSpectators = true;
    bool allowMidGameJoin = false;
    final timeLimitController = TextEditingController(text: '30');
    final targetScoreController = TextEditingController(text: '1000');
    String selectedGameType = 'tichu';
    bool advancedOpen = false;
    final Set<String> skExpansionsSelected = <String>{};
    String? errorText;
    void Function(void Function())? dialogSetState;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          dialogSetState = setState;
          final themeColors = context.read<GameService>().themeGradient;
          final accent = themeColors.length > 1
              ? themeColors[1]
              : themeColors.first;

          InputDecoration fieldDecoration(
            String hintText, {
            String? suffixText,
          }) {
            OutlineInputBorder b(Color c, double w) => OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: c, width: w),
            );
            return InputDecoration(
              hintText: hintText,
              hintStyle: Cartoon.text(
                size: 15,
                color: Cartoon.ink.withValues(alpha: 0.4),
              ),
              suffixText: suffixText,
              suffixStyle: Cartoon.text(size: 14),
              filled: true,
              fillColor: Cartoon.paper,
              border: b(Cartoon.ink, 2.5),
              enabledBorder: b(Cartoon.ink, 2.5),
              focusedBorder: b(Cartoon.orange, 3),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
            );
          }

          // Title only. Each section also carried a sentence restating what the
          // controls under it obviously do ("플레이할 게임을 선택합니다" over a game
          // picker), which is most of the dialog's height and none of its
          // information. The parameter stays so call sites don't all change.
          Widget sectionTitle(String title, String subtitle) {
            return Text(title, style: Cartoon.text(size: 16));
          }

          Widget optionCard({
            required String title,
            String? description,
            required bool value,
            required ValueChanged<bool> onChanged,
            bool enabled = true,
            IconData? icon,
            Color? iconColor,

            /// Artwork instead of a glyph, for options that ship their own.
            String? iconAsset,
          }) {
            // A row with a divider, not a card. Each option used to be its own
            // bordered box whose border colour also encoded the value — a card
            // per switch inside a card inside the dialog, saying with a border
            // what the switch already says.
            //
            // The glyph is the same one the option produces out in the lobby
            // (the eye on a room card, the arrow on a mid-join room), so the
            // switch and its consequence are recognisably the same thing —
            // four near-identical text rows were easy to mix up.
            return Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0x22000000))),
                ),
                child: Row(
                  children: [
                    if (icon != null || iconAsset != null) ...[
                      // No plate behind them. The artwork carries its own
                      // colour, and a tinted square under it read as a button
                      // — which these rows are not; the switch on the right is.
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: iconAsset != null
                            ? (cartoonIconForAsset(iconAsset) ??
                                  Image.asset(iconAsset, fit: BoxFit.contain))
                            : Icon(
                                icon,
                                size: 20,
                                color:
                                    iconColor ??
                                    Cartoon.onSurface(const Color(0xFF7A6A62)),
                              ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Cartoon.text(
                              size: 15,
                              color: enabled
                                  ? Cartoon.ink
                                  : Cartoon.ink.withValues(alpha: 0.45),
                            ),
                          ),
                          // Only where the switch has consequences you cannot
                          // see (ranked pins the score and clears private).
                          if (description != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 11,
                                color: enabled
                                    ? Cartoon.onSurface(const Color(0xFF7E7069))
                                    : const Color(0xFFAAA09C),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      value: value,
                      onChanged: enabled ? onChanged : null,
                      activeTrackColor: Cartoon.green,
                      activeThumbColor: Colors.white,
                      inactiveTrackColor: Colors.white,
                      inactiveThumbColor: Cartoon.ink,
                      trackOutlineColor: WidgetStatePropertyAll(Cartoon.ink),
                      trackOutlineWidth: const WidgetStatePropertyAll(2.5),
                    ),
                  ],
                ),
              ),
            );
          }

          // Keyboard-first dismissal: while the keyboard is up, a tap on the
          // barrier (or the back button) closes the KEYBOARD, not the dialog —
          // losing half-entered settings to a mis-tap is worse than needing a
          // second tap to leave. Taps inside the dialog on non-interactive
          // space also just drop focus.
          final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;
          void selectGame(String type) {
            setState(() {
              selectedGameType = type;
              randomName = _generateRandomRoomName(
                gameType: selectedGameType,
                l10n: l10n,
              );
              if (selectedGameType == 'skull_king' ||
                  selectedGameType == 'love_letter' ||
                  selectedGameType == 'mighty') {
                isRanked = false;
              }
              if (selectedGameType == 'mighty') {
                targetScoreController.text = '50';
              } else if (selectedGameType == 'tichu') {
                targetScoreController.text = '1000';
              }
            });
          }

          return PopScope(
            canPop: !keyboardUp,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) FocusManager.instance.primaryFocus?.unfocus();
            },
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(color: Cartoon.ink, width: 2.2),
                ),
                backgroundColor: Cartoon.paper,
                contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
                content: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: SingleChildScrollView(
                    // No inner panel: the dialog already has a background, and a
                    // gradient box inside it just drew a second edge around the
                    // same content.
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      // Stack so the game picker can FLOAT over the options below
                      // instead of pushing them down — expanding in place made the
                      // whole dialog taller every time it opened.
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // No title: you arrive here by pressing "새 방 만들기", and
                              // the confirm button at the bottom says it again. Same for
                              // the section captions above a game picker and a name
                              // field — they named what was already visible.
                              const SizedBox(height: 4),
                              // 드롭다운 대신 네 게임을 한눈에 — 눌러서 바로 고른다.
                              // 펼쳐지는 목록이 아래 옵션 위로 겹치던 문제가 없어진다.
                              Row(
                                children: [
                                  for (final (i, t) in const [
                                    'tichu',
                                    'mighty',
                                    'skull_king',
                                    'love_letter',
                                  ].indexed) ...[
                                    if (i > 0) const SizedBox(width: 6),
                                    Expanded(
                                      child: CartoonPressable(
                                        onTap: () => selectGame(t),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 160,
                                          ),
                                          margin: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selectedGameType == t
                                                ? gameTypeColor(t)
                                                : Cartoon.paper,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            border: Border.all(
                                              color: Cartoon.ink,
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Cartoon.ink,
                                                offset: Offset(
                                                  0,
                                                  selectedGameType == t ? 4 : 2,
                                                ),
                                              ),
                                            ],
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              AnimatedScale(
                                                scale: selectedGameType == t
                                                    ? 1.18
                                                    : 1.0,
                                                duration: const Duration(
                                                  milliseconds: 380,
                                                ),
                                                curve: Curves.elasticOut,
                                                child: gameTypeSymbol(
                                                  t,
                                                  size: 34,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                gameTypeLabel(l10n, t),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Cartoon.text(
                                                  size: 14,
                                                  color: selectedGameType == t
                                                      ? Colors.white
                                                      : Cartoon.ink,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (selectedGameType == 'skull_king') ...[
                                const SizedBox(height: 14),
                                Text(
                                  l10n.lobbyExpansionOptional,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                // One row, three equal buttons; pressed = filled. The
                                // switch rows this replaces read as three settings —
                                // these are a pick-any-of-three, which is a button
                                // group. The one-line effect stays as the caption.
                                Row(
                                  children: [
                                    for (final (i, entry) in [
                                      [
                                        'kraken',
                                        l10n.lobbyExpKraken,
                                        l10n.lobbyExpKrakenDesc,
                                      ],
                                      [
                                        'white_whale',
                                        l10n.lobbyExpWhiteWhale,
                                        l10n.lobbyExpWhiteWhaleDesc,
                                      ],
                                      [
                                        'loot',
                                        l10n.lobbyExpLoot,
                                        l10n.lobbyExpLootDesc,
                                      ],
                                      [
                                        'pirate_abilities',
                                        l10n.lobbyExpPirate,
                                        l10n.lobbyExpPirateDesc,
                                      ],
                                    ].indexed) ...[
                                      if (i > 0) const SizedBox(width: 6),
                                      Expanded(
                                        child: Builder(
                                          builder: (_) {
                                            final selected =
                                                skExpansionsSelected.contains(
                                                  entry[0],
                                                );
                                            // 확장팩마다 자기 테마 색: 크라켄 보라,
                                            // 흰고래 하늘, 약탈 금색. 안 눌렀을 땐 회색,
                                            // 누르면 그 확장팩의 색이 찬다.
                                            final (
                                              strong,
                                              emoji,
                                            ) = switch (entry[0]) {
                                              'kraken' => (
                                                Cartoon.onSurface(
                                                  const Color(0xFF7B3FC4),
                                                ),
                                                '🐙',
                                              ),
                                              'white_whale' => (
                                                Cartoon.onSurface(
                                                  const Color(0xFF1E88D6),
                                                ),
                                                '🐳',
                                              ),
                                              'pirate_abilities' => (
                                                Cartoon.onSurface(
                                                  const Color(0xFFC0392B),
                                                ),
                                                '🏴‍☠️',
                                              ),
                                              _ => (
                                                const Color(0xFFE29A00),
                                                '💰',
                                              ),
                                            };
                                            return CartoonPressable(
                                              scale: 0.95,
                                              onTap: () => setState(() {
                                                if (selected) {
                                                  skExpansionsSelected.remove(
                                                    entry[0],
                                                  );
                                                } else {
                                                  skExpansionsSelected.add(
                                                    entry[0],
                                                  );
                                                }
                                              }),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 150,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                      horizontal: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: selected
                                                      ? strong
                                                      : Cartoon.surface(
                                                          const Color(
                                                            0xFFE6E1DB,
                                                          ),
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  border: Border.all(
                                                    color: selected
                                                        ? Cartoon.ink
                                                        : Cartoon.ink
                                                              .withValues(
                                                                alpha: 0.4,
                                                              ),
                                                    width: selected ? 2.6 : 1.8,
                                                  ),
                                                ),
                                                child: Column(
                                                  children: [
                                                    FittedBox(
                                                      fit: BoxFit.scaleDown,
                                                      child: Text(
                                                        '$emoji ${entry[1]}',
                                                        maxLines: 1,
                                                        style: Cartoon.userText(
                                                          size: 13,
                                                          weight:
                                                              FontWeight.w800,
                                                          color: selected
                                                              ? Colors.white
                                                              : Cartoon.ink
                                                                    .withValues(
                                                                      alpha:
                                                                          0.55,
                                                                    ),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      entry[2],
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: Cartoon.userText(
                                                        size: 10,
                                                        weight: FontWeight.w600,
                                                        color: selected
                                                            ? Colors.white
                                                                  .withValues(
                                                                    alpha: 0.9,
                                                                  )
                                                            : Cartoon.ink
                                                                  .withValues(
                                                                    alpha: 0.45,
                                                                  ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                              const SizedBox(height: 16),
                              // Name field with the dice on the same line. The random
                              // button was a low-contrast text button floating above the
                              // field, easy to miss entirely.
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: controller,
                                      decoration: fieldDecoration(randomName),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Material(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () => setState(() {
                                        randomName = _generateRandomRoomName(
                                          gameType: selectedGameType,
                                          l10n: l10n,
                                        );
                                        controller.text = randomName;
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.all(11),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFD8CCC6),
                                          ),
                                        ),
                                        // Dark, not the pale theme accent — it was
                                        // nearly invisible against the white square.
                                        child: Icon(
                                          Icons.casino,
                                          size: 20,
                                          color: Cartoon.onSurface(
                                            Cartoon.onSurface(
                                              const Color(0xFF6A5A52),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              CartoonPressable(
                                scale: 0.97,
                                onTap: () => setState(
                                  () => advancedOpen = !advancedOpen,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Cartoon.cream,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: Cartoon.ink,
                                      width: 2,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.tune, color: Cartoon.ink),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.lobbyGameSettings,
                                        style: Cartoon.text(size: 16),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          [
                                            if (isPrivate)
                                              l10n.lobbyPrivateRoom,
                                            if (isRanked) l10n.lobbyRanked,
                                            '${timeLimitController.text}${l10n.lobbySuffixSeconds}',
                                          ].join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.end,
                                          style: Cartoon.text(
                                            size: 13,
                                            color: Cartoon.ink.withValues(
                                              alpha: 0.6,
                                            ),
                                          ),
                                        ),
                                      ),
                                      AnimatedRotation(
                                        turns: advancedOpen ? 0.5 : 0,
                                        duration: const Duration(
                                          milliseconds: 220,
                                        ),
                                        child: Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Cartoon.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              AnimatedSize(
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (advancedOpen) ...[
                                      const SizedBox(height: 8),
                                      optionCard(
                                        iconAsset: 'assets/icons/private.webp',
                                        iconColor: Cartoon.onSurface(
                                          const Color(0xFF7A6A62),
                                        ),
                                        title: l10n.lobbyPrivateRoom,
                                        description: isRanked
                                            ? l10n.lobbyPrivateRoomDescRanked
                                            : null,
                                        value: isPrivate,
                                        enabled: !isRanked,
                                        onChanged: (v) =>
                                            setState(() => isPrivate = v),
                                      ),
                                      if (isPrivate) ...[
                                        const SizedBox(height: 10),
                                        TextField(
                                          controller: passwordController,
                                          obscureText: true,
                                          decoration: fieldDecoration(
                                            l10n.lobbyPasswordHint,
                                          ),
                                        ),
                                      ],
                                      optionCard(
                                        iconAsset:
                                            'assets/icons/allowSpectators.webp',
                                        title: l10n.lobbyAllowSpectators,
                                        value: allowSpectators,
                                        onChanged: (v) => setState(() {
                                          allowSpectators = v;
                                          // Breaking in means breaking in from the
                                          // spectator seat, so the option below cannot
                                          // outlive spectating. The server enforces the
                                          // same dependency; dropping it here keeps the
                                          // switch from reading as on when it isn't.
                                          if (!v) allowMidGameJoin = false;
                                        }),
                                      ),
                                      optionCard(
                                        iconAsset:
                                            'assets/icons/allowBotReplacement.webp',
                                        iconColor: Cartoon.onSurface(
                                          const Color(0xFF4A4080),
                                        ),
                                        title: l10n.midJoinCreateOption,
                                        description: isRanked
                                            ? null
                                            : l10n.midJoinCreateOptionHint,
                                        value: allowMidGameJoin,
                                        // Ranked rooms hold no bots, so there is never
                                        // a seat to take over.
                                        enabled: !isRanked && allowSpectators,
                                        onChanged: (v) => setState(
                                          () => allowMidGameJoin = v,
                                        ),
                                      ),
                                      if (selectedGameType != 'love_letter' &&
                                          context
                                                  .read<GameService>()
                                                  .authProvider !=
                                              'local') ...[
                                        optionCard(
                                          iconAsset:
                                              'assets/icons/lankIcon.webp',
                                          iconColor: const Color(0xFFD9A036),
                                          title: l10n.lobbyRanked,
                                          description:
                                              selectedGameType == 'skull_king'
                                              ? l10n.lobbyRankedDescSk
                                              : selectedGameType == 'mighty'
                                              ? l10n.lobbyRankedDescMighty
                                              : l10n.lobbyRankedDesc,
                                          value: isRanked,
                                          onChanged: (v) => setState(() {
                                            isRanked = v;
                                            if (isRanked) {
                                              isPrivate = false;
                                              passwordController.clear();
                                              targetScoreController.text =
                                                  selectedGameType == 'mighty'
                                                  ? '50'
                                                  : '1000';
                                            }
                                          }),
                                        ),
                                      ],
                                      const SizedBox(height: 16),
                                      sectionTitle(
                                        l10n.lobbyGameSettings,
                                        (selectedGameType == 'tichu' ||
                                                selectedGameType == 'mighty')
                                            ? l10n.lobbyGameSettingsDescTichu
                                            : l10n.lobbyGameSettingsDescSk,
                                      ),
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  l10n.lobbyTimeLimit,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                TextField(
                                                  controller:
                                                      timeLimitController,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                    LengthLimitingTextInputFormatter(
                                                      3,
                                                    ),
                                                  ],
                                                  textAlign: TextAlign.center,
                                                  decoration: fieldDecoration(
                                                    l10n.lobbyTimeLimitRange,
                                                    suffixText:
                                                        l10n.lobbySuffixSeconds,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (selectedGameType == 'tichu' ||
                                              selectedGameType == 'mighty') ...[
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    l10n.lobbyTargetScore,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  TextField(
                                                    controller:
                                                        targetScoreController,
                                                    enabled: !isRanked,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter
                                                          .digitsOnly,
                                                      LengthLimitingTextInputFormatter(
                                                        5,
                                                      ),
                                                    ],
                                                    textAlign: TextAlign.center,
                                                    decoration: fieldDecoration(
                                                      isRanked
                                                          ? (selectedGameType ==
                                                                    'mighty'
                                                                ? l10n.lobbyTargetScoreFixedMighty
                                                                : l10n.lobbyTargetScoreFixed)
                                                          : (selectedGameType ==
                                                                    'mighty'
                                                                ? l10n.lobbyTargetScoreRangeMighty
                                                                : l10n.lobbyTargetScoreRange),
                                                      suffixText: l10n
                                                          .lobbySuffixPoints,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              // The info box that sat here restated things already on
                              // screen: the ranked rules are the ranked toggle's own
                              // description, and the valid ranges are the fields'
                              // placeholders (out-of-range input is clamped anyway).
                              if (errorText != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Cartoon.surface(
                                      Cartoon.surface(const Color(0xFFFFECEC)),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFF2B3B3),
                                    ),
                                  ),
                                  child: Text(
                                    errorText!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Cartoon.onSurface(
                                        Cartoon.onSurface(
                                          const Color(0xFFB54A4A),
                                        ),
                                      ),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.commonCancel),
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      final name = controller.text.trim().isEmpty
                          ? randomName
                          : controller.text.trim();
                      final password = passwordController.text.trim();
                      if (name.isEmpty) {
                        dialogSetState?.call(
                          () => errorText = l10n.lobbyEnterRoomName,
                        );
                        return;
                      }
                      if (isPrivate && password.length < 4) {
                        dialogSetState?.call(
                          () => errorText = l10n.lobbyPasswordTooShort,
                        );
                        return;
                      }
                      final turnTimeLimit =
                          (int.tryParse(timeLimitController.text.trim()) ?? 30)
                              .clamp(10, 999);
                      final targetScore = isRanked
                          ? (selectedGameType == 'mighty' ? 50 : 1000)
                          : selectedGameType == 'mighty'
                          ? (int.tryParse(targetScoreController.text.trim()) ??
                                    50)
                                .clamp(10, 500)
                          : (int.tryParse(targetScoreController.text.trim()) ??
                                    1000)
                                .clamp(100, 20000);
                      context.read<GameService>().createRoom(
                        name,
                        password: isPrivate ? password : '',
                        isRanked: isRanked,
                        turnTimeLimit: turnTimeLimit,
                        targetScore: targetScore,
                        gameType: selectedGameType,
                        maxPlayers: selectedGameType == 'skull_king'
                            ? 6
                            : selectedGameType == 'mighty'
                            ? 6
                            : selectedGameType == 'love_letter'
                            ? 4
                            : 4,
                        skExpansions: selectedGameType == 'skull_king'
                            ? skExpansionsSelected.toList()
                            : const [],
                        allowSpectators: allowSpectators,
                        allowMidGameJoin: allowMidGameJoin,
                      );
                      Navigator.pop(context);
                      setState(() => _inRoom = true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      // 바탕이 테마 그라데이션에서 온다. 진한 색을 박아
                      // 두면 어두운 테마에서 남색 위에 검정이 된다.
                      foregroundColor: Cartoon.inkOn(accent),
                      textStyle: const TextStyle(
                        fontFamily: Cartoon.font,
                        fontSize: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: Cartoon.ink, width: 2),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      l10n.lobbyCreateRoom,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;
    final missionGame = context.read<GameService>();
    // 로비가 그려질 때마다 한 프레임 뒤에 확인한다: 미션 상태 요청, 안내 말풍선 띄우기·치우기.
    final landscapeNow =
        !kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMissionHint(missionGame, landscapeNow);
    });
    // Same call the game screen makes: the landscape variants are built for a
    // tablet held sideways, and the app no longer rotates at all, so on the web
    // they are the only place that code runs — untested by everyone else. It
    // shows: the landscape lobby packs notices and errors into a bordered
    // utility box, which is not how the app has ever presented them.
    final isLandscape =
        !kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    return Theme(
      data: cartoonTheme(Theme.of(context)),
      child: ConnectionOverlay(
        child: PopScope(
          // Never let the pop through: on the web that would walk the browser
          // off the site mid-session, and on Android it would drop to the home
          // screen. What back MEANS is decided below instead.
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            // In a waiting room, back is the header's ← — the one thing on this
            // screen there is to back out of. Anywhere else (the lobby itself,
            // the login form) there is nothing behind, so it stays a no-op
            // rather than doing something surprising.
            //
            // Games and the spectator view are other screens with their own
            // PopScope; they still swallow it, so nobody leaves a live hand by
            // reaching for the back button.
            final game = context.read<GameService>();
            if (!_inRoom && game.currentDestination == AppDestination.lobby) {
              return;
            }
            _leaveRoom(game);
          },
          child: Scaffold(
            // On the web the engine has already shrunk its canvas to the visual
            // viewport by the time the keyboard is up, so letting the Scaffold
            // subtract viewInsets on top of that takes the keyboard height off
            // twice and leaves an empty band above the keyboard. Native keeps the
            // default, where the inset is the only thing doing the resizing.
            resizeToAvoidBottomInset: kIsWeb ? false : null,
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: themeColors,
                ),
              ),
              // 아래 안전영역은 화면이 직접 채운다 — 로비 하단 탭이 그 영역까지
              // 이어져야 해서, 여기서 비워 두면 탭 밑에 배경색 띠가 보였다.
              child: SafeArea(
                bottom: false,
                child: Consumer<GameService>(
                  builder: (context, game, _) {
                    // Handle duplicate login kick
                    if (game.duplicateLoginKicked) {
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        if (!mounted) return;
                        if (!game.consumeDuplicateLoginKick()) return;
                        final session = context.read<SessionService>();
                        final messenger = ScaffoldMessenger.of(context);
                        final duplicateLoginMessage = L10n.of(
                          context,
                        ).lobbyDuplicateLoginKicked;
                        await session.logout();
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(duplicateLoginMessage),
                            backgroundColor: Cartoon.red,
                          ),
                        );
                      });
                    }
                    // Show room invite dialog if any
                    if (game.hasRoomInvites) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        final invite = game.firstRoomInvite;
                        if (invite == null) return;
                        game.dismissInvite(0);
                        _showRoomInviteDialog(invite, game);
                      });
                    }

                    // Sync local room flag with server state
                    if (!game.hasRoom && _inRoom) {
                      _inRoom = false;
                      // Back on the lobby: re-check for a reply popup deferred
                      // while in a room (no further notify is guaranteed).
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _onInquiryUpdate(),
                      );
                    }
                    // Spectators land here too now — the waiting room is one
                    // screen for both.
                    if (game.isInRoomWithoutGame && !_inRoom) {
                      _inRoom = true;
                    }

                    final destination = game.currentDestination;

                    if (destination != AppDestination.lobby || _inRoom) {
                      _inRoom = true;
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom,
                        ),
                        child: _buildRoomView(game, isLandscape: isLandscape),
                      );
                    }
                    final lobby = _buildLobbyView(
                      game,
                      isLandscape: isLandscape,
                    );
                    // 세로는 하단 탭이 안전영역까지 덮고, 가로는 탭이 없으니 여기서 띄운다.
                    return isLandscape
                        ? Padding(
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.paddingOf(context).bottom,
                            ),
                            child: lobby,
                          )
                        : lobby;
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobbyView(GameService game, {required bool isLandscape}) {
    final Widget body;
    if (isLandscape) {
      final hasTopNotices =
          game.hasMaintenanceNotice ||
          game.inquiryBannerMessage != null ||
          game.errorMessage != null;
      body = Column(
        children: [
          _buildLobbyHeader(game, isLandscape: true),
          if (game.matchIncoming) _buildMatchIncomingBanner(),
          if (hasTopNotices)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildLandscapeLobbyUtilityBar(game),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _buildRoomListPanel(game),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        children: [
          _buildLobbyHeader(game, isLandscape: false),

          if (game.matchIncoming) _buildMatchIncomingBanner(),

          // Maintenance notice banner
          if (game.hasMaintenanceNotice) _buildMaintenanceBanner(game),
          if (game.inquiryBannerMessage != null) _buildInquiryBanner(game),
          if (game.errorMessage != null) _buildErrorBanner(game.errorMessage!),

          // Room list or Friends panel
          Expanded(child: _buildRoomListPanel(game)),
        ],
      );
    }

    return Column(
      children: [
        Expanded(child: body),
        if (!isLandscape) _buildLobbyBottomNav(game),
      ],
    );
  }

  Widget _buildLandscapeLobbyUtilityBar(GameService game) {
    final hasTopNotices =
        game.hasMaintenanceNotice ||
        game.inquiryBannerMessage != null ||
        game.errorMessage != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Cartoon.surface(Colors.white).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Cartoon.surface(const Color(0xFFE9DED9))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (hasTopNotices)
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (game.hasMaintenanceNotice) _buildMaintenanceBanner(game),
                  if (game.inquiryBannerMessage != null)
                    _buildInquiryBanner(game),
                  if (game.errorMessage != null)
                    _buildErrorBanner(game.errorMessage!),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLobbyHeader(GameService game, {required bool isLandscape}) {
    // 세로: 로고 + 내 골드만. 버튼 다섯 개는 글자가 붙은 하단 탭으로 내려갔다.
    if (!isLandscape) return _buildSimpleLobbyHeader(game);
    return CartoonEntrance(
      from: const Offset(0, -40),
      child: Container(
        // Same both ways round now. Landscape used to be roomier horizontally
        // and tighter vertically for no reason that survived the buttons
        // growing; a ternary that returns the same number twice only reads as
        // an intention nobody has.
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 2.5),
        margin: EdgeInsets.fromLTRB(
          isLandscape ? 12 : 16,
          isLandscape ? 12 : 16,
          isLandscape ? 12 : 16,
          isLandscape ? 16 : 20,
        ),
        clipBehavior: Clip.none,
        // The row is measured before it is built. Five buttons at a fixed size
        // fit a normal phone and nothing else: narrower and they wrap onto a
        // second line, wider (a fold, a browser) and there is no reason for them
        // to keep growing — a 60px store icon is not easier to hit.
        //
        // The buttons are served first and the logo takes what is left, because
        // the buttons are what the header is FOR. Reversed, a wide logo pushed
        // them onto their own line on a 320px phone.
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gaps = _headerButtonGap * (_headerButtonCount - 1);
            final forButtons =
                constraints.maxWidth -
                _headerLogoMinWidth -
                _headerLogoGap -
                gaps;
            final box = (forButtons / _headerButtonCount).clamp(
              _headerButtonMin,
              _headerButtonMax,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Transform.translate(
                      offset: const Offset(0, 7),
                      child: ConstrainedBox(
                        // Capped so it does not sprawl on a wide window, and
                        // free to shrink below that on a narrow one.
                        constraints: BoxConstraints(
                          maxHeight: isLandscape ? 36 : _headerButtonMax,
                          maxWidth: _headerLogoMaxWidth,
                        ),
                        child: Image.asset(
                          'assets/dragon_icon.webp',
                          fit: BoxFit.contain,
                          alignment: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: _headerLogoGap),
                // A Row, not a Wrap: the size above is chosen so they fit, and a
                // Wrap would quietly hide a miscalculation by growing a second
                // line instead of showing it.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (i, button) in _buildLobbyActionButtons(
                      game,
                      box,
                    ).indexed) ...[
                      if (i > 0) const SizedBox(width: _headerButtonGap),
                      button,
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _withCommas(int n) => n.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );

  Widget _buildSimpleLobbyHeader(GameService game) {
    return CartoonEntrance(
      from: const Offset(0, -40),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
        decoration: Cartoon.panelDecoration(radius: 18, shadowOffset: 2.5),
        child: Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomLeft,
                // 패널 아래 선에 맞춰 하단 정렬 — 패딩만큼 내려 선 위에 걸터앉게.
                child: Transform.translate(
                  offset: const Offset(0, 7),
                  // 패널 높이는 그대로 두고 그림만 위로 키운다.
                  child: SizedBox(
                    height: 44,
                    width: 190,
                    child: OverflowBox(
                      alignment: Alignment.bottomLeft,
                      maxHeight: 52,
                      maxWidth: 190,
                      child: Image.asset(
                        'assets/dragon_icon.webp',
                        height: 52,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomLeft,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // 룰북 — 골드 왼쪽 빈자리에. 설정 안에도 그대로 있다.
            CartoonPressable(
              scale: 0.9,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RulesScreen()),
              ),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Cartoon.cream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Cartoon.ink, width: 2),
                  boxShadow: [
                    BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                  ],
                ),
                child: const RulebookIcon(size: 30),
              ),
            ),
            const SizedBox(width: 8),
            CartoonPressable(
              scale: 0.93,
              onTap: () => showGoldHistoryDialog(context, game),
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                decoration: BoxDecoration(
                  color: Cartoon.cream,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Cartoon.ink, width: 2),
                  boxShadow: [
                    BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GoldIcon(size: 28, amount: game.gold),
                    const SizedBox(width: 6),
                    Text(
                      game.walletLoaded ? _withCommas(game.gold) : '…',
                      style: Cartoon.text(size: 18),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 하단 탭: 상점 · 친구 · 랭킹 · 내 프로필 · 설정. 아이콘만 있던 헤더 버튼에
  /// 글자를 붙여, 처음 온 사람도 무엇인지 알 수 있게 했다. 누르는 동작과 배지는
  /// 예전 헤더 버튼을 그대로 가져온다.
  Widget _buildLobbyBottomNav(GameService game) {
    final l10n = L10n.of(context);
    final buttons = _buildLobbyActionButtons(game, 46);
    final labels = [
      l10n.shopTitle,
      l10n.friendsTitle,
      l10n.rankingTitle,
      l10n.missionsTitle,
      l10n.lobbyMyProfile,
      l10n.settingsTitle,
    ];
    return CartoonEntrance(
      from: const Offset(0, 50),
      delay: const Duration(milliseconds: 200),
      child: Container(
        padding: EdgeInsets.fromLTRB(
          6,
          10,
          6,
          6 + MediaQuery.paddingOf(context).bottom,
        ),
        decoration: BoxDecoration(
          color: Cartoon.paper,
          border: Border(top: BorderSide(color: Cartoon.ink, width: 2.2)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Row(
          children: [
            for (var i = 0; i < buttons.length; i++)
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    buttons[i],
                    const SizedBox(height: 5),
                    Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Cartoon.text(size: 12.5),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ───────────── 오늘의 미션 안내(뱃지 + 말풍선) ─────────────

  void _hideMissionHint() {
    _missionHintTimer?.cancel();
    _missionHintTimer = null;
    _missionHint?.remove();
    _missionHint = null;
  }

  /// 미션 상태를 받아 오고, 오늘 미션을 안 골랐으면 안내를 띄우고, 조건이 사라지면 치운다.
  void _syncMissionHint(GameService game, bool landscape) {
    if (!game.isLoggedIn) return;
    final inLobby =
        !_inRoom &&
        !game.hasRoom &&
        game.currentDestination == AppDestination.lobby;
    // 상태가 없거나 날이 바뀌었으면 (너무 자주는 말고) 다시 받는다.
    if (inLobby && game.missionsNeedRefresh && !game.missionsLoading) {
      final last = _missionsRequestedAt;
      if (last == null || DateTime.now().difference(last).inSeconds >= 30) {
        _missionsRequestedAt = DateTime.now();
        game.requestMissions();
      }
    }
    final resetKey = game.missionsState?.resetAtUtc?.toIso8601String();
    // 계정이 바뀌면 다른 키가 되어야 한다 — 위 선언 머리말 참고.
    final dayKey = resetKey == null ? null : '${game.playerName}@$resetKey';
    final wanted =
        inLobby &&
        game.hasUnpickedMissionsToday &&
        dayKey != null &&
        _missionHintShownFor != dayKey;
    if (_missionHint != null && !(inLobby && game.hasUnpickedMissionsToday)) {
      _hideMissionHint(); // 골랐거나 로비를 떠났다
      return;
    }
    if (!wanted || _missionHint != null) return;
    _missionHintShownFor = dayKey;
    final l10n = L10n.of(context);
    _missionHint = OverlayEntry(
      builder: (_) => Positioned(
        left: 0,
        top: 0,
        child: CompositedTransformFollower(
          link: _missionLink,
          showWhenUnlinked: false,
          // 세로: 하단 탭 위에서 꼬리가 아래를 가리킨다. 가로: 상단 버튼 아래에서 위를 가리킨다.
          targetAnchor: landscape
              ? Alignment.bottomCenter
              : Alignment.topCenter,
          followerAnchor: landscape
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          offset: Offset(0, landscape ? 8 : -8),
          child: HintBubble(
            text: l10n.missionsPickHint,
            pointsDown: !landscape,
            onTap: () {
              _hideMissionHint();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MissionsScreen()),
              );
            },
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_missionHint!);
    _missionHintTimer = Timer(const Duration(seconds: 7), _hideMissionHint);
  }

  List<Widget> _buildLobbyActionButtons(GameService game, double box) {
    final attendance = game.attendanceState;
    // Never on the web: the attendance banner inside the shop is hidden there
    // (the daily reward needs a rewarded ad, and AdMob has no web build), so a
    // dot pointing at it would send players to a screen with nothing to claim.
    // Same condition as _shouldShowAttendanceBanner in shop_screen.
    final attendanceUnclaimed =
        !kIsWeb && attendance != null && attendance['claimedToday'] != true;
    return [
      Stack(
        children: [
          _buildIconButton(
            icon: Icons.store,
            color: const Color(0xFFFFB74D),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ShopScreen()),
              );
            },
            box: box,
          ),
          if (attendanceUnclaimed)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Cartoon.onSurface(const Color(0xFFE53935)),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Cartoon.surface(Colors.white),
                    width: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
      Stack(
        children: [
          _buildIconButton(
            icon: Icons.people,
            color: Cartoon.onSurface(const Color(0xFF7E57C2)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              );
            },
            box: box,
          ),
          if ((game.pendingFriendRequestCount + game.totalUnreadDmCount) > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Cartoon.onSurface(const Color(0xFFE53935)),
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  '${game.pendingFriendRequestCount + game.totalUnreadDmCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      _buildIconButton(
        icon: Icons.leaderboard,
        color: const Color(0xFF81C784),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RankingScreen()),
          );
        },
        box: box,
      ),
      // 미션 — 토큰을 모아 토큰 상점에서 꾸미기를 산다.
      // 뱃지: 새로 깬 미션이 있으면 숫자, 오늘 미션을 아직 안 골랐으면 빨간 점.
      CompositedTransformTarget(
        link: _missionLink,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _buildIconButton(
              icon: Icons.task_alt_rounded,
              color: const Color(0xFFFF8A65),
              onTap: () {
                _hideMissionHint();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MissionsScreen()),
                );
              },
              box: box,
            ),
            if (game.missionBadgeCount > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Cartoon.onSurface(const Color(0xFFE53935)),
                    borderRadius: const BorderRadius.all(Radius.circular(999)),
                    border: Border.all(
                      color: Cartoon.surface(Colors.white),
                      width: 1.5,
                    ),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    game.missionBadgeCount > 9
                        ? '9+'
                        : '${game.missionBadgeCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (game.hasUnpickedMissionsToday)
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Cartoon.onSurface(const Color(0xFFE53935)),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Cartoon.surface(Colors.white),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      // Own profile, in the slot the rulebook used to sit in. The rulebook
      // moved into settings: it is read once and then never again, while your
      // own profile is the thing you actually reach for from the lobby.
      // Shows the player's photo when they have one so the row reads as
      // "you" rather than as another generic icon.
      _buildMyProfileButton(game, box),
      Stack(
        clipBehavior: Clip.none,
        children: [
          _buildIconButton(
            icon: Icons.settings,
            color: Cartoon.onSurface(const Color(0xFF9E9E9E)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    onShowMyProfile: (settingsCtx) {
                      final game = context.read<GameService>();
                      _showUserProfileDialog(
                        game.playerName,
                        game,
                        dialogContext: settingsCtx,
                      );
                    },
                  ),
                ),
              );
            },
            box: box,
          ),
          // Badge covers BOTH unread notices and unread inquiry replies, so an
          // answered inquiry is discoverable on the room-list page (settings →
          // 문의내역) instead of relying on the transient banner.
          if (game.unreadNoticeCount +
                  game.unreadInquiryReplyCount +
                  game.unreadMailCount >
              0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Cartoon.onSurface(const Color(0xFFE53935)),
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  (game.unreadNoticeCount +
                              game.unreadInquiryReplyCount +
                              game.unreadMailCount) >
                          9
                      ? '9+'
                      : '${game.unreadNoticeCount + game.unreadInquiryReplyCount + game.unreadMailCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    ];
  }

  Widget _buildMatchIncomingBanner() {
    // A deploy is moving our match to this server. It lands here when the
    // round in progress on the old one finishes, and the server puts us back
    // in automatically — so say that rather than leave the lobby looking like
    // the game disappeared.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Cartoon.surface(Cartoon.surface(const Color(0xFFDEDBFA))),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF9A8FE8)),
      ),
      child: Row(
        children: [
          // Not a spinner: nothing is loading here and the wait is on the
          // other server finishing its round. This says "your game is being
          // moved here", which is what is actually happening.
          Icon(
            Icons.swap_horiz_rounded,
            size: 20,
            color: Cartoon.onSurface(const Color(0xFF4A4080)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              L10n.of(context).lobbyMatchIncoming,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Cartoon.onSurface(const Color(0xFF4A4080)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceBanner(GameService game) {
    String timeText = '';
    if (game.maintenanceStart != null && game.maintenanceEnd != null) {
      try {
        final start = DateTime.parse(game.maintenanceStart!).toLocal();
        final end = DateTime.parse(game.maintenanceEnd!).toLocal();
        String fmt(DateTime d) =>
            '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        timeText = '${fmt(start)} ~ ${fmt(end)}';
      } catch (_) {}
    }
    return _noticeBar(
      icon: Icons.construction_rounded,
      color: Cartoon.yellow,
      text: game.maintenanceMessage.isNotEmpty
          ? game.maintenanceMessage
          : L10n.of(context).lobbyMaintenanceDefault,
      subText: timeText,
      userText: game.maintenanceMessage.isNotEmpty,
    );
  }

  /// 로비 위쪽 알림 줄(점검·문의 답변·오류) 공통 모양: 색 아이콘 칩 + 글자, 옅은 바탕에
  /// 얇은 테두리. 상자를 늘리지 않으려고 그림자는 없다.
  Widget _noticeBar({
    required IconData icon,
    required Color color,
    required String text,
    String subText = '',
    bool userText = false,
    Widget? trailing,
  }) {
    final style = userText
        ? Cartoon.userText(size: 15)
        : Cartoon.text(size: 16, height: 1.25);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: Cartoon.tint(color, 0.75),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Cartoon.ink, width: 1.6),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: Cartoon.ink, width: 1.6),
            ),
            child: Icon(icon, color: Cartoon.ink, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: style),
                if (subText.isNotEmpty)
                  Text(
                    subText,
                    style: Cartoon.text(
                      size: 13,
                      color: Cartoon.ink.withValues(alpha: 0.6),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }

  Widget _buildInquiryBanner(GameService game) {
    return _noticeBar(
      icon: Icons.mark_email_read_rounded,
      color: Cartoon.blue,
      text: localizeInquiryBanner(game.inquiryBannerMessage, L10n.of(context)),
      trailing: CartoonPressable(
        scale: 0.85,
        onTap: () => game.requestInquiries(),
        child: Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.refresh_rounded, size: 22, color: Cartoon.ink),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return _noticeBar(
      icon: Icons.warning_rounded,
      color: Cartoon.red,
      text: localizeServiceMessage(message, L10n.of(context)),
    );
  }

  Widget _buildRoomListPanel(GameService game) {
    // No panel card: the rows inside are already surfaces, so the white box
    // around them was one more border to look past — same as the waiting room.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The "게임 방 리스트" caption said nothing you could not see, so the
              // row it occupied now carries the game filters instead.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // 위·아래 여백: 가로 스크롤 영역은 자기 높이 밖을 잘라 낸다. 선택된
                  // 칩은 1.08배로 커지고 그림자도 아래로 나가서, 여백이 없으면
                  // 위쪽 테두리가 잘려 보였다.
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.fromLTRB(3, 7, 3, 4),
                  child: Row(children: _buildGameFilterChips()),
                ),
              ),
              _RefreshChip(onTap: game.requestRoomList),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            // 방 만들기는 목록 위에 떠 있는 알약 버튼 — 목록이 화면을 다 쓰고,
            // 엄지가 닿는 오른쪽 아래에 있다.
            child: Stack(
              children: [
                RefreshIndicator(
                  onRefresh: () async {
                    game.requestRoomList();
                    await Future.delayed(const Duration(milliseconds: 500));
                  },
                  child: !game.roomListReceived
                      ? _buildRoomListLoading()
                      : (game.roomList.isEmpty
                            ? _buildEmptyRoomList()
                            : _buildRoomList(game.roomList)),
                ),
                Positioned(
                  right: 4,
                  bottom: 6,
                  child: CartoonEntrance(
                    delay: const Duration(milliseconds: 450),
                    from: const Offset(0, 40),
                    child: CartoonPulse(
                      child: CartoonButton(
                        expand: false,
                        height: 54,
                        color: Cartoon.green,
                        onPressed: _showCreateRoomDialog,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 14, right: 20),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                              const SizedBox(width: 4),
                              CartoonButton.label(
                                L10n.of(context).lobbyCreateRoom,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // removed separate spectate list; in-progress rooms are shown inline

  // Scrollable so RefreshIndicator can pull even when the content doesn't fill
  // the viewport.
  Widget _fillScrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildRoomListLoading() {
    return _fillScrollable(
      Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(
          color: Cartoon.onSurface(const Color(0xFF8A7A72)),
        ),
      ),
    );
  }

  Widget _buildEmptyRoomList() =>
      _buildEmptyState(L10n.of(context).lobbyEmptyRoomList);

  /// 방이 없을 때: 졸고 있는 마스코트. 방 만들기 버튼은 목록 아래에 이미 있으니
  /// 여기엔 따로 두지 않는다 (같은 버튼이 두 개 보이던 문제).
  Widget _buildEmptyState(String message) {
    return _fillScrollable(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CartoonFloat(
              amplitude: 8,
              child: Image.asset(
                'assets/dragon_head.webp',
                width: 96,
                height: 96,
                color: Colors.white.withValues(alpha: 0.35),
                colorBlendMode: BlendMode.modulate,
              ),
            ),
            const SizedBox(height: 4),
            Cartoon.outlinedText('Zzz…', size: 24, fill: Cartoon.skyTop),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Cartoon.text(size: 17, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  /// 전체, then one chip per game. The selected one is filled in that game's
  /// colour — the same colour as its strip and badge in the rows below, so the
  /// filter and the thing it filters read as the same family.
  ///
  /// Picking one, not hiding one. Tapping a chip labelled 티츄 has to show
  /// Tichu; the previous toggle did the reverse, and isolating a single game
  /// meant tapping the other three.
  List<Widget> _buildGameFilterChips() {
    final l10n = L10n.of(context);
    // 전체 carries the app's own brown rather than any game's colour, so it
    // never looks like a fifth game.
    final chips = <(String?, String, Color)>[
      (null, l10n.lobbyFilterAll, Cartoon.onSurface(const Color(0xFF7A6A62))),
      ('tichu', l10n.lobbyTichu, const Color(0xFF64B5F6)),
      (
        'mighty',
        l10n.rankingMighty,
        Cartoon.onSurface(const Color(0xFF5C6BC0)),
      ),
      (
        'skull_king',
        l10n.lobbySkullKing,
        Cartoon.onSurface(const Color(0xFF21455F)),
      ),
      (
        'love_letter',
        l10n.lobbyLoveLetter,
        Cartoon.onSurface(const Color(0xFFE91E63)),
      ),
    ];
    return [
      for (final (type, label, color) in chips)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: CartoonPressable(
            // Tapping the selected game again goes back to 전체, so getting out
            // of a filter never needs you to find the 전체 chip.
            onTap: () => setState(
              () => _roomGameFilter = _roomGameFilter == type ? null : type,
            ),
            child: AnimatedScale(
              scale: _roomGameFilter == type ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 380),
              curve: Curves.elasticOut,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                margin: const EdgeInsets.only(bottom: 3),
                decoration: BoxDecoration(
                  color: _roomGameFilter == type ? color : Cartoon.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Cartoon.ink, width: 2),
                  boxShadow: _roomGameFilter == type
                      ? null
                      : [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
                ),
                child: Text(
                  label,
                  style: Cartoon.text(
                    size: 14,
                    color: _roomGameFilter == type ? Colors.white : Cartoon.ink,
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildRoomList(List<Room> allRooms) {
    final rooms = filterRoomsByGame(
      allRooms,
      _roomGameFilter,
      (r) => r.gameType,
    );
    if (rooms.isEmpty) {
      return _buildEmptyState(L10n.of(context).lobbyNoRoomsForFilter);
    }
    // Waiting rooms on top, in-progress rooms at the bottom.
    // Stable sort so server-provided order is preserved within each group.
    final sorted = [...rooms]
      ..sort((a, b) {
        if (a.gameInProgress == b.gameInProgress) return 0;
        return a.gameInProgress ? 1 : -1;
      });
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      // 떠 있는 방 만들기 버튼 밑으로 마지막 카드가 가려지지 않게.
      padding: const EdgeInsets.only(bottom: 92),
      itemCount: sorted.length,
      // 줄 아래 구분선은 각 줄이 직접 그린다 — 방이 하나뿐이어도 아래 선이 남도록.
      separatorBuilder: (_, _) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final room = sorted[index];
        // 새로 나타난 방만 통통 등장한다 (id 로 구분). 처음 목록이 뜰 때는
        // 위에서부터 차례로.
        return CartoonEntrance(
          key: ValueKey('room-${room.id}'),
          delay: Duration(milliseconds: 45 * index.clamp(0, 6)),
          from: const Offset(0, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildRoomItem(room),
              Divider(
                height: 1,
                thickness: 1.5,
                indent: 8,
                endIndent: 8,
                color: Cartoon.ink.withValues(alpha: 0.12),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 스컬킹 확장팩의 테마 색(크라켄 보라·흰고래 파랑·약탈 금색)과 이모지.
  Color _skExpansionStrongColor(String expansionId) {
    switch (expansionId) {
      case 'kraken':
        return Cartoon.onSurface(const Color(0xFF7B3FC4));
      case 'white_whale':
        return Cartoon.onSurface(const Color(0xFF1E88D6));
      case 'loot':
        return const Color(0xFFE29A00);
      case 'pirate_abilities':
        return Cartoon.onSurface(const Color(0xFFC0392B));
      default:
        return Cartoon.onSurface(const Color(0xFF6A5A52));
    }
  }

  String _skExpansionEmoji(String expansionId) {
    switch (expansionId) {
      case 'kraken':
        return '🐙';
      case 'white_whale':
        return '🐳';
      case 'loot':
        return '💰';
      case 'pirate_abilities':
        return '🏴‍☠️';
      default:
        return '';
    }
  }

  String _skExpansionShortLabel(String expansionId, L10n l10n) {
    switch (expansionId) {
      case 'kraken':
        return l10n.lobbyExpKrakenShort;
      case 'white_whale':
        return l10n.lobbyExpWhaleShort;
      case 'loot':
        return l10n.lobbyExpLootShort;
      case 'pirate_abilities':
        return l10n.lobbyExpPirateShort;
      default:
        return expansionId;
    }
  }

  Widget _buildRoomItem(Room room) {
    final isInProgress = room.gameInProgress;
    final isSK = room.isSkullKing;
    final isLL = room.gameType == 'love_letter';
    final isMighty = room.gameType == 'mighty';
    final l10n = L10n.of(context);

    // Only the left strip and the game badge carry the game's colour. Every game
    // used to repaint the whole row — background, border, name, subtitle, and a
    // second variant for in-progress — so eight colour sets turned the list into
    // a swatch chart and nothing stood out inside a row.
    final Color stripColor;
    final Color badgeBgColor;
    final String badgeText;
    const badgeTextColor = Colors.white;

    // Both take the shared palette — these were a fourth hand-written copy of
    // the same four colours.
    stripColor = gameTypeColor(room.gameType);
    badgeBgColor = stripColor;
    if (isLL) {
      badgeText = l10n.lobbyLoveLetterBadge;
    } else if (isMighty) {
      badgeText = l10n.lobbyMightyBadge;
    } else if (isSK) {
      badgeText = l10n.lobbySkullKingBadge;
    } else {
      badgeText = l10n.lobbyTichuBadge;
    }

    // 토큰 상점 '방 목록 강조' — 방장이 장착했으면 줄에 틀과 표식이 붙는다.
    final highlight = roomHighlightFor(room.highlight);

    return Material(
      // A match already running greys the whole cell instead of wearing a
      // "게임 중" chip. The state belongs to the room, not to one corner of
      // it, and saying it with the surface costs no width — which is what the
      // row had run out of.
      // 상자 없이 한 줄씩 — 줄 사이는 구분선이 나눈다.
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          if (isInProgress) {
            _spectateWithPasswordCheck(room);
            return;
          }
          if (room.isRanked &&
              context.read<GameService>().authProvider == 'local') {
            _showRankedSocialRequiredDialog();
            return;
          }
          if (room.isPrivate) {
            _showJoinPrivateRoomDialog(room);
            return;
          }
          context.read<GameService>().joinRoom(room.id);
          setState(() => _inRoom = true);
        },
        borderRadius: BorderRadius.circular(16),
        child: MaybeRoomHighlight(
          style: highlight,
          child: Container(
            // 진행 중인 방은 옅게 가라앉힌다. 그림자가 없으니 반투명이어도 된다.
            decoration: BoxDecoration(
              color: highlight == null && isInProgress
                  ? const Color(0x14000000)
                  : null,
              borderRadius: BorderRadius.circular(16),
            ),
            // Clip the contents to the card's INNER curve instead of asking the
            // strip to round itself. A 16px radius on a 6px-wide box is not a
            // shape Flutter can draw — it scales the corners down to fit, so the
            // strip's curve came out tighter than the card's and read as
            // misaligned. And the radius here is 15, not 16: the border is 1px
            // wide and the strip sits inside it.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left color strip — stretches to cell height. Square-cornered
                    // on purpose; the ClipRRect above gives it the card's curve.
                    Container(width: 7, color: stripColor),
                    Expanded(
                      child: Padding(
                        // Tightened again (was 11/9). What the padding gives
                        // up goes into the type and the icons below: the row is
                        // read at arm's length in a list of a dozen, so legible
                        // content beats air around it.
                        padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        margin: const EdgeInsets.only(right: 7),
                                        decoration: BoxDecoration(
                                          color: badgeBgColor,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          badgeText,
                                          style: Cartoon.text(
                                            size: 13,
                                            color: badgeTextColor,
                                          ),
                                        ),
                                      ),
                                      // Was emoji glued onto the front of the name
                                      // string ('🔒 🏆 이름'). Real widgets instead:
                                      // the trophy is now the same artwork as the
                                      // ranked switch in the create dialog, and an
                                      // emoji rendered next to it would read as a
                                      // different badge from a different set.
                                      if (room.isPrivate) ...[
                                        const _LockChip(size: 24),
                                        const SizedBox(width: 6),
                                      ],
                                      if (room.isRanked) ...[
                                        RankedIcon(width: 20, height: 18),
                                        const SizedBox(width: 4),
                                      ],
                                      Expanded(
                                        child: Text(
                                          room.name,
                                          // 방 이름은 사용자가 정한 글자라 Jua 서브셋에
                                          // 없는 글자가 올 수 있다 — 기본 글꼴로.
                                          style: Cartoon.userText(
                                            size: 18,
                                            color: highlight?.inkOn,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 2,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 2,
                                        ),
                                        child: Text(
                                          (isSK || isLL)
                                              ? l10n.lobbyRoomTimeSec(
                                                  room.turnTimeLimit,
                                                )
                                              : l10n.lobbyRoomTimeAndScore(
                                                  room.turnTimeLimit,
                                                  room.targetScore,
                                                ),
                                          style: Cartoon.text(
                                            size: 13,
                                            color: Cartoon.ink.withValues(
                                              alpha: 0.62,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (isSK && room.skExpansions.isNotEmpty)
                                        for (final exp in room.skExpansions)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _skExpansionStrongColor(
                                                exp,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Cartoon.ink,
                                                width: 1.4,
                                              ),
                                            ),
                                            child: Text(
                                              _skExpansionEmoji(exp).isEmpty
                                                  ? _skExpansionShortLabel(
                                                      exp,
                                                      l10n,
                                                    )
                                                  : _skExpansionEmoji(exp),
                                              style: Cartoon.userText(
                                                size: 12,
                                                color: Colors.white,
                                                weight: FontWeight.w800,
                                                height: 1.0,
                                              ),
                                            ),
                                          ),
                                      if (room.allowMidGameJoin)
                                        Tooltip(
                                          message: l10n.midJoinRoomBadge,
                                          // Geometry copied from the spectate button beside
                                          // it (8/7 padding, 16px glyph, radius 10) so the
                                          // two read as one pair of room actions rather than
                                          // two unrelated marks. Only the colour differs, and
                                          // that difference is the whole message: purple =
                                          // you can get in, not just watch.
                                          child: Container(
                                            // Tighter than the eye button's 8/7 because this
                                            // glyph is wider than tall: same outer box, more
                                            // of it spent on the artwork.
                                            // Bare artwork — no plate, no border. Four
                                            // boxed chips in a row read as a toolbar; the
                                            // icons alone read as what the room is.
                                            padding: const EdgeInsets.only(
                                              left: 4,
                                            ),
                                            // Availability rides on opacity, since artwork
                                            // can't be recoloured and a second symbol would
                                            // undo the point of using this one: full when a
                                            // seat is free right now, faded when it is only
                                            // the room's rule.
                                            child: Opacity(
                                              opacity: room.canJoinInProgress
                                                  ? 1.0
                                                  : 0.4,
                                              child: BotSwapIcon(
                                                width: 28,
                                                height: 23,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (room.allowSpectators)
                                        GestureDetector(
                                          onTap: () =>
                                              _spectateWithPasswordCheck(room),
                                          child: Container(
                                            // Still the tap target that opens spectating —
                                            // the padding keeps it thumb-sized without a
                                            // border drawing a button around it.
                                            padding: const EdgeInsets.fromLTRB(
                                              2,
                                              4,
                                              8,
                                              4,
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const EyeIcon(
                                                  width: 28,
                                                  height: 22,
                                                ),
                                                if (room.spectatorCount >
                                                    0) ...[
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${room.spectatorCount}',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Cartoon.onSurface(
                                                        Cartoon.onSurface(
                                                          const Color(
                                                            0xFF7A6A62,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // The eye used to mean two different things: a button
                            // that takes you into spectating (waiting rooms) and a
                            // read-out of how many people are already watching
                            // (running games). Now the button is always the button,
                            // and the count only appears when there is one.
                            // A running game you can actually get into, not just
                            // watch. Sits next to the "playing" chip because that
                            // is the chip it qualifies — without it, a match in
                            // progress reads as closed.
                            // Marks every room running this rule, not only the ones
                            // you could jump into this second — it is what the room
                            // IS, and it decides whether you want to sit down here
                            // at all (leaving hands your seat to a bot and counts
                            // against you). Filled when a seat is actually free to
                            // take right now, outlined when it is just the rule:
                            // same fact, two different invitations.
                            // Glyph only. Spelled out it was the widest thing in a
                            // row that already carries the playing chip, the eye
                            // and the seat count — and it was pushing the room name
                            // out of a card whose whole job is showing the name.
                            // The label lives on the tooltip and on the badge in
                            // the waiting room, where there is space for it.
                            // Shown whatever the room is doing: it is a property of
                            // the room, and it decides whether you want to sit down
                            // here at all — leaving hands your seat to a bot and
                            // counts against you. Filled when a seat is free to take
                            // this second, outlined when it is only the rule.
                            // Seats only. Whether the match is running is carried
                            // by the cell's own background now, so nothing here
                            // has to spend width repeating it.
                            Tooltip(
                              message: isInProgress
                                  ? l10n.lobbyRoomPlaying
                                  : l10n.lobbyRoomWaiting,
                              child: _SeatDots(
                                filled: room.playerCount,
                                total: room.effectiveMaxPlayers,
                                color: stripColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRankedSocialRequiredDialog() {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _dialogTitle(
          Icons.lock_rounded,
          Cartoon.yellow,
          l10n.lobbySocialLinkRequired,
        ),
        content: Text(
          l10n.lobbySocialLinkRequiredDesc,
          style: Cartoon.text(size: 16, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonOk),
          ),
        ],
      ),
    );
  }

  void _showJoinPrivateRoomDialog(Room room) {
    final l10n = L10n.of(context);
    _showPasswordDialog(
      title: l10n.lobbyJoinPrivateRoom,
      buttonText: l10n.lobbyEnter,
      onSubmit: (password) {
        context.read<GameService>().joinRoom(room.id, password: password);
        setState(() => _inRoom = true);
      },
    );
  }

  void _spectateWithPasswordCheck(Room room) {
    if (room.isPrivate) {
      final l10n = L10n.of(context);
      _showPasswordDialog(
        title: l10n.lobbySpectatePrivateRoom,
        buttonText: l10n.lobbySpectate,
        onSubmit: (password) {
          context.read<GameService>().spectateRoom(room.id, password: password);
        },
      );
    } else {
      context.read<GameService>().spectateRoom(room.id);
    }
  }

  void _showPasswordDialog({
    required String title,
    required String buttonText,
    required void Function(String password) onSubmit,
  }) {
    final controller = TextEditingController();
    final l10n = L10n.of(context);
    void submit(BuildContext ctx) {
      final password = controller.text.trim();
      if (password.isEmpty) return;
      Navigator.pop(ctx);
      onSubmit(password);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        scrollable: true,
        backgroundColor: Cartoon.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Cartoon.ink, width: 2.2),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        title: Row(
          children: [
            const _LockChip(size: 36),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: Cartoon.text(size: 20))),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          style: Cartoon.userText(size: 18),
          onSubmitted: (_) => submit(ctx),
          decoration: Cartoon.inputDecoration(
            hint: l10n.lobbyPassword,
            icon: Icons.vpn_key_rounded,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel, style: Cartoon.text(size: 17)),
          ),
          CartoonButton(
            expand: false,
            height: 46,
            onPressed: () => submit(ctx),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: CartoonButton.label(buttonText, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  /// Seats, and under them the docked chat.
  ///
  /// The chat is a sibling of the scroll area, not the last thing inside it:
  /// inside, it would scroll away exactly when someone is typing, and its own
  /// list would be a scroller in a scroller.
  ///
  /// The seats take only the height they need, so the chat starts right under
  /// the start button rather than at the bottom of the screen with a field of
  /// nothing between them, and then fills everything left. Only when the seats
  /// would need more than that leaves do they scroll, and the chat keeps its
  /// floor — which rises while the keyboard is up.
  Widget _buildRoomBody(GameService game) {
    if (!_roomChatDocked) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        child: _buildRoomPlayersPanel(game),
      );
    }
    // Built here rather than inside the builder below. LayoutBuilder runs its
    // builder on every constraint change, which during the keyboard slide is
    // every frame; handing it the same widget instances lets updateChild take
    // its identity fast path instead of rebuilding six seats per frame.
    final seats = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
      child: _buildRoomPlayersPanel(game),
    );
    final chat = _buildDockedRoomChat(game);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Where the seat guarantee is actually made. These constraints are the
        // box the seats and the chat share — the screen minus the header, the
        // safe areas and the banner ad — so this is the only place that can
        // hold 130dp back for the seats. Clamping the chat's floor against the
        // full screen instead (as the drag handler must, not knowing this box)
        // would let a height dragged on a tall screen swallow the entire body
        // on a shorter one: seats zero, start button gone, chat only.
        //
        // Neither side may reach zero. A body too short for both minimums has
        // to shortchange someone, and that is the seats: they scroll, so a
        // thin strip of them is still usable, whereas a chat below its title
        // bar plus input row just overflows and paints a stripe.
        final chatCeiling = math.max(
          _dockedChatHardMinHeight,
          constraints.maxHeight - _dockedChatSeatMinHeight,
        );
        final minChat = math.min(
          _dockedChatMinHeightNow(),
          math.min(chatCeiling, constraints.maxHeight),
        );
        final seatMax = math.max(0.0, constraints.maxHeight - minChat);
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: seatMax),
              child: seats,
            ),
            Expanded(child: chat),
          ],
        );
      },
    );
  }

  /// Leave the waiting room. Shared by the header's ← and the back button, so
  /// the two can't drift into meaning different things.
  void _leaveRoom(GameService game) {
    game.leaveRoom();
    setState(() => _inRoom = false);
    // No immediate re-check here: _inRoom flips to false before the server
    // confirms, so the strengthened _onInquiryUpdate guard would defer
    // anyway. The server-confirm notify re-fires the listener once truly on
    // the lobby.
  }

  Widget _buildRoomView(GameService game, {required bool isLandscape}) {
    final isKoreanUser =
        context.read<LocaleService>().effectiveLocale.languageCode == 'ko';
    _seatChat.consume(game);
    if (_roomChatDocked || _roomChatOpen) {
      _roomChatRead = game.chatMessages.length;
    }
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        // Tapping the room closes the drop menu, the way tapping outside a
        // popup does.
        if (_roomMoreOpen) setState(() => _roomMoreOpen = false);
      },
      child: Stack(
        children: [
          Column(
            children: [
              _buildRoomHeader(game, isLandscape: isLandscape),

              // Maintenance notice banner (in waiting room)
              if (game.hasMaintenanceNotice) _buildMaintenanceBanner(game),

              // Error message banner
              if (game.errorMessage != null)
                _buildErrorBanner(game.errorMessage!),

              Expanded(child: _buildRoomBody(game)),
              if (_roomBannerAd != null && _roomBannerLoaded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: SizedBox(
                      height: _roomBannerAd!.size.height.toDouble(),
                      width: _roomBannerAd!.size.width.toDouble(),
                      child: AdWidget(
                        ad: _roomBannerAd!,
                        key: ValueKey(_roomBannerAd!.hashCode),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (!_roomChatDocked && _roomChatOpen) _buildRoomChatPanel(game),
          if (_roomMoreOpen) _buildRoomMoreMenu(game, isKoreanUser),
        ],
      ),
    );
  }

  /// Share the room: copy the invite link, or hand it to KakaoTalk.
  ///
  /// The button used to go straight to Kakao, which is a dead end for anyone not
  /// sharing there — the link itself works anywhere.
  void _showShareRoomSheet(GameService game, bool isKoreanUser) {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Cartoon.ink.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(l10n.lobbyShareSheetTitle, style: Cartoon.text(size: 21)),
              const SizedBox(height: 8),
              _shareSheetTile(
                icon: Icons.link,
                label: l10n.lobbyShareCopyLink,
                onTap: () async {
                  Navigator.pop(ctx);
                  final url = await game.createShareInviteLink();
                  if (!mounted) return;
                  if (url == null || url.isEmpty) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(l10n.commonError)),
                    );
                    return;
                  }
                  await Clipboard.setData(ClipboardData(text: url));
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.lobbyShareCopied)),
                  );
                },
              ),
              if (isKoreanUser)
                _shareSheetTile(
                  icon: Icons.chat_bubble,
                  label: l10n.lobbyShareKakao,
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await KakaoInviteShareService.instance.shareRoomInvite(
                        game,
                      );
                    } catch (error) {
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text(error.toString())),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _shareSheetTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Cartoon.cream,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: Cartoon.ink),
      ),
      title: Text(label, style: Cartoon.text(size: 17)),
      trailing: Icon(Icons.chevron_right_rounded, color: Cartoon.ink),
      onTap: onTap,
    );
  }

  /// Icon-only action in the waiting room header.
  /// What [nickname] just said, or null once it has timed out.
  Widget? _seatChatBubble(String nickname) {
    final text = _seatChat.textFor(nickname);
    if (text == null) return null;
    return Positioned(
      left: 62,
      right: 10,
      top: 6,
      bottom: 6,
      child: Align(
        alignment: Alignment.centerLeft,
        child: SeatChatBubble(
          text: text,
          styleKey: _seatChat.styleFor(nickname),
        ),
      ),
    );
  }

  Widget _roomIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    int badge = 0,
  }) {
    return CartoonPressable(
      scale: 0.88,
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(left: 6, bottom: 3),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: active
                  ? Cartoon.orange
                  : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              size: 21,
              color: active ? Colors.white : Cartoon.ink,
            ),
          ),
          if (badge > 0)
            Positioned(
              right: -5,
              top: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Cartoon.red,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: Cartoon.inkOn(Cartoon.red),
                    width: 1.4,
                  ),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The icon row that drops out from under the header's ⋯.
  ///
  /// This replaces the "room tools" bottom sheet: a modal list for three
  /// shortcuts was heavier than the shortcuts. Each entry keeps a small caption —
  /// four bare icons would be a guessing game, and two of them (switch to
  /// spectating vs. see who is spectating) used to both be an eye.
  Widget _buildRoomMoreMenu(GameService game, bool isKoreanUser) {
    final l10n = L10n.of(context);
    final unread = game.pendingFriendRequestCount + game.totalUnreadDmCount;
    return Positioned(
      top: 70,
      right: 12,
      child: AnimatedOpacity(
        opacity: _roomMoreOpen ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: AnimatedScale(
          scale: _roomMoreOpen ? 1 : 0.95,
          duration: const Duration(milliseconds: 160),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: Cartoon.panelDecoration(radius: 20, shadowOffset: 2.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _roomMoreItem(
                  icon: Icons.share_rounded,
                  label: l10n.lobbyShareSheetTitle,
                  onTap: () => _showShareRoomSheet(game, isKoreanUser),
                ),
                _roomMoreItem(
                  icon: Icons.forum_outlined,
                  label: l10n.lobbyFriendsDm,
                  badgeCount: unread,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const FriendsScreen()),
                  ),
                ),
                // Changes what YOU are in the room. A spectator is already
                // one, and their way back is the 착석 button on a seat.
                if (!game.isSpectator)
                  _roomMoreItem(
                    icon: Icons.swap_horiz,
                    label: l10n.lobbySwitchToSpectator,
                    onTap: () => game.switchToSpectator(),
                  ),
                // Shows who else is watching.
                _roomMoreItem(
                  icon: Icons.people_outline,
                  label: l10n.lobbySpectatorListTitle,
                  badgeCount: game.spectators.length,
                  onTap: () => showSpectatorListDialog(context, game),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One entry in the ⋯ row: icon button with a small caption under it.
  Widget _roomMoreItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _roomMoreOpen = false);
          onTap();
        },
        child: SizedBox(
          width: 62,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Cartoon.cream,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Cartoon.ink, width: 1.6),
                    ),
                    child: Icon(icon, size: 21, color: Cartoon.ink),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Cartoon.red,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: Cartoon.inkOn(Cartoon.red),
                            width: 1.4,
                          ),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Cartoon.userText(
                  size: 10,
                  weight: FontWeight.w800,
                  color: Cartoon.ink.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoomHeader(GameService game, {required bool isLandscape}) {
    // Flat bar, not a floating card — same treatment as the spectator header.
    // Three stacked cards (header, players, chat) put three elevations on one
    // screen, and the 16dp margin on every side cost width the room title needs.
    return Container(
      // 상자 없이 화면 위에 바로 — 헤더까지 상자면 대기실이 상자투성이였다.
      margin: EdgeInsets.fromLTRB(8, isLandscape ? 2 : 4, 8, 2),
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      // One row: back, a title block (room name + its rules underneath), then
      // icon-only actions. It was two rows — title with two chips and a share
      // button, then four labelled pastel chips — which spent ~110dp of height
      // and still truncated the room name. Labels moved into the icons' own
      // affordance; switch-to-spectator moved into the ⋯ sheet.
      child: Row(
        children: [
          CartoonPressable(
            scale: 0.88,
            onTap: () => _leaveRoom(game),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Cartoon.surface(Colors.white).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(Icons.arrow_back_rounded, color: Cartoon.ink),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Builder(
              builder: (_) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.currentRoomName,
                      style: Cartoon.userText(
                        size: 18,
                        weight: FontWeight.w900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // 방 정보는 이 한 줄로 — 알약 줄을 따로 두면 화면을 너무 먹었다.
                    Builder(
                      builder: (_) {
                        final l10n = L10n.of(context);
                        final type = game.currentGameType;
                        final total = game.effectiveRoomMaxPlayers;
                        final full = game.playerCount >= total;
                        final hasScore = type == 'tichu' || type == 'mighty';
                        final info = [
                          gameTypeLabel(l10n, type),
                          '${game.roomTurnTimeLimit}${l10n.lobbySuffixSeconds}',
                          if (hasScore)
                            '${game.roomTargetScore}${l10n.lobbySuffixPoints}',
                        ].join(' · ');
                        return Text.rich(
                          TextSpan(
                            style: Cartoon.userText(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: Cartoon.ink.withValues(alpha: 0.62),
                            ),
                            children: [
                              TextSpan(text: '$info · '),
                              TextSpan(
                                text: '${game.playerCount}/$total',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: full
                                      ? Cartoon.onSurface(
                                          const Color(0xFF2E9E4F),
                                        )
                                      : Cartoon.onSurface(
                                          const Color(0xFFE5791A),
                                        ),
                                ),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          // Only while the chat floats. Docked, it is always on screen, so a
          // show/hide button would either do nothing or take the chat away
          // with no way back that looks like a way back.
          if (!_roomChatDocked)
            _roomIconButton(
              icon: Icons.chat_bubble_outline_rounded,
              active: _roomChatOpen,
              badge: _roomChatOpen
                  ? 0
                  : math.max(0, game.chatMessages.length - _roomChatRead),
              onTap: () => setState(() {
                _roomChatOpen = !_roomChatOpen;
                if (_roomChatOpen) {
                  _roomChatRead = game.chatMessages.length;
                  _roomMoreOpen = false;
                  _scrollChatToBottom();
                }
              }),
            ),
          // 이 방에 들어간 확장팩 카드를 미리 본다.
          //
          // 확장팩은 방을 만들 때 정해지고 바꿀 수 없다. 처음 보는 카드가
          // 무슨 일을 하는지는 그 카드가 트릭을 가져간 뒤가 아니라 그 전에
          // 알아야 쓸모가 있어서, 게임 화면에만 있던 안내를 여기서도 연다.
          //
          // 확장팩이 없는 방(또는 스컬킹이 아닌 방)에서는 버튼도 없다 —
          // 눌러도 빈 시트가 뜨는 버튼은 없느니만 못하다.
          if (game.currentGameType == 'skull_king' &&
              game.roomSkExpansions.isNotEmpty)
            _roomIconButton(
              icon: Icons.style_rounded,
              onTap: () => showSkExpansionGuide(context, game.roomSkExpansions),
            ),
          // Inviting is a seat-holder's business: an invitee joins the room,
          // and a spectator has no standing to fill it.
          if (!game.isSpectator)
            _roomIconButton(
              icon: Icons.person_add_alt_1,
              onTap: () => _showInviteFriendsDialog(game),
            ),
          // Host-only anyway, so it belongs in the row — hiding it behind ⋯ did
          // not save a non-host anything.
          if (game.isHost)
            _roomIconButton(
              icon: Icons.settings,
              onTap: () => _showRoomSettingsDialog(game),
            ),
          _roomIconButton(
            icon: Icons.more_horiz,
            active: _roomMoreOpen,
            onTap: () => setState(() => _roomMoreOpen = !_roomMoreOpen),
          ),
        ],
      ),
    );
  }

  /// Seats in two columns.
  ///
  /// One seat per row made a six-player Skull King room a column taller than
  /// the phone it was on, and left the docked chat nothing. The same room in
  /// two columns is half as tall. Tichu's fixed-team view already read this
  /// way; this is the same shape for the games with no teams to separate.
  ///
  /// An odd seat count leaves the last cell empty rather than stretching that
  /// seat across both columns — full width at the bottom of a grid reads as a
  /// different kind of thing (a button, a banner) than the seats above it.
  Widget _buildSeatGrid(GameService game) {
    // Tight on purpose: the seats already read as separate cards (each has its
    // own fill and border), so the gap only has to keep them from touching.
    //
    // The same 6 is used for the screen edge (see _buildRoomBody). A larger
    // edge inset reads as the left and right margins being bigger than the top
    // and bottom ones, because next to a 6 gap that is exactly what it is.
    const gap = 6.0;
    final slots = game.roomPlayers;
    final rows = <Widget>[];
    for (int i = 0; i < slots.length; i += 2) {
      final right = i + 1;
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildClickablePlayerSlot(
                slots[i],
                slotIndex: i,
                game: game,
              ),
            ),
            const SizedBox(width: gap),
            Expanded(
              child: right < slots.length
                  ? _buildClickablePlayerSlot(
                      slots[right],
                      slotIndex: right,
                      game: game,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (i + 2 < slots.length) rows.add(const SizedBox(height: gap));
    }
    return Column(children: rows);
  }

  Widget _teamPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Cartoon.ink, width: 1.6),
      ),
      child: Cartoon.outlinedText(label, size: 15),
    );
  }

  Widget _buildRoomPlayersPanel(GameService game) {
    // No card of its own: the seat rows inside already carry their own fills,
    // and wrapping them in a white panel on a tinted page just added a border to
    // look past.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          if (game.isRankedRoom) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Cartoon.surface(
                  Cartoon.surface(const Color(0xFFFFE9B8)),
                ),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: Cartoon.ink, width: 1.6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The artwork, not the emoji — same trophy the create
                  // dialog's ranked switch shows, so the room you are sitting
                  // in is recognisably the option you turned on.
                  RankedIcon(width: 20, height: 17),
                  const SizedBox(width: 6),
                  Text(
                    game.currentGameType == 'skull_king'
                        ? L10n.of(context).lobbySkullKingRanked
                        : game.currentGameType == 'mighty'
                        ? L10n.of(context).lobbyMightyRanked
                        : L10n.of(context).lobbyTichuRanked,
                    style: Cartoon.text(
                      size: 15,
                      color: Cartoon.onSurface(const Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),
            // Same visibility the custom-room branch below gives — ranked SK
            // expansions are host-picked too (nothing forces a fixed set for
            // ranked), so without this chip row the only place to see them
            // was mid-game, past the point of backing out.
            if (game.currentGameType == 'skull_king' &&
                game.roomSkExpansions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final exp in game.roomSkExpansions)
                    _buildSkExpansionChip(exp),
                ],
              ),
            ],
            const SizedBox(height: 12),
            // Ranked Tichu stays one per row: its seats are teams (0+2 vs
            // 1+3), and a grid would sit 0 next to 1 and say the opposite.
            if (game.currentGameType == 'tichu')
              for (int i = 0; i < game.roomPlayers.length; i++) ...[
                _buildClickablePlayerSlot(
                  game.roomPlayers[i],
                  slotIndex: i,
                  game: game,
                ),
                if (i < game.roomPlayers.length - 1) const SizedBox(height: 6),
              ]
            else
              _buildSeatGrid(game),
          ] else if (game.currentGameType == 'skull_king' ||
              game.currentGameType == 'love_letter' ||
              game.currentGameType == 'mighty') ...[
            // (게임 종류·인원 배지는 위 방 정보 알약으로 옮겼다)
            // SK expansion chips: give the waiting-room members visibility
            // into which expansions the host enabled without having to leave
            // and re-read the room tile.
            if (game.currentGameType == 'skull_king' &&
                game.roomSkExpansions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final exp in game.roomSkExpansions)
                    _buildSkExpansionChip(exp),
                ],
              ),
            ],
            if (game.roomAllowMidGameJoin) ...[
              const SizedBox(height: 8),
              _buildMidGameJoinBadge(game),
            ],
            const SizedBox(height: 12),
            _buildSeatGrid(game),
          ] else ...[
            // Compact random-team chip for non-ranked Tichu. Host taps to
            // toggle; non-hosts see the current state as read-only.
            if (game.currentGameType == 'tichu' && !game.isRankedRoom) ...[
              _buildRandomSeatingChip(game),
              const SizedBox(height: 12),
            ],
            if (game.roomAllowMidGameJoin) ...[
              _buildMidGameJoinBadge(game),
              const SizedBox(height: 12),
            ],
            // 팀 배치는 네 자리(0·2 대 1·3)를 그대로 찍어 읽는다. 방을
            // 옮기는 찰나에는 게임 종류가 아직 티츄인 채로 자리 수만 먼저
            // 바뀌어 있을 수 있어서(스컬킹 2인 방에 들어가는 순간 등)
            // roomPlayers[2] 를 읽다 터졌다. 자리가 모자라면 격자로 그린다.
            if (game.roomRandomSeating || game.roomPlayers.length < 4)
              // No teams to keep apart here — they are drawn at start — so
              // the grid is free to pair whoever is adjacent.
              _buildSeatGrid(game)
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _teamPill('TEAM A', const Color(0xFF6AA9E8)),
                        const SizedBox(height: 8),
                        _buildClickablePlayerSlot(
                          game.roomPlayers[0],
                          slotIndex: 0,
                          game: game,
                        ),
                        const SizedBox(height: 6),
                        _buildClickablePlayerSlot(
                          game.roomPlayers[2],
                          slotIndex: 2,
                          game: game,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: [
                        _teamPill('TEAM B', const Color(0xFFF08A9A)),
                        const SizedBox(height: 8),
                        _buildClickablePlayerSlot(
                          game.roomPlayers[1],
                          slotIndex: 1,
                          game: game,
                        ),
                        const SizedBox(height: 6),
                        _buildClickablePlayerSlot(
                          game.roomPlayers[3],
                          slotIndex: 3,
                          game: game,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 12),
          if (game.isHost &&
              !game.isRankedRoom &&
              _hasFillableEmptySlot(game)) ...[
            _buildFillEmptyBotsRow(game),
            const SizedBox(height: 12),
          ],
          // Ready and start belong to whoever is sitting down. A spectator
          // gets neither — the way in is the 착석 button on a seat.
          if (game.isSpectator)
            const SizedBox.shrink()
          else if (game.isHost) ...[
            Builder(
              builder: (_) {
                final canStart =
                    game.currentGameType == 'skull_king' ||
                        game.currentGameType == 'love_letter'
                    ? game.playerCount >= 2
                    : game.currentGameType == 'mighty'
                    ? game.playerCount >= 5
                    : game.playerCount >= game.effectiveRoomMaxPlayers;
                if (!canStart) {
                  // 숨기지 않고 비활성으로 보여 준다 — 버튼이 없으면 "왜 시작을
                  // 못 하지?" 가 되고, 이렇게 두면 몇 명이 더 필요한지가 보인다.
                  final need =
                      (game.currentGameType == 'skull_king' ||
                              game.currentGameType == 'love_letter'
                          ? 2
                          : game.currentGameType == 'mighty'
                          ? 5
                          : game.effectiveRoomMaxPlayers) -
                      game.playerCount;
                  return FractionallySizedBox(
                    widthFactor: 0.8,
                    child: CartoonButton(
                      height: 56,
                      onPressed: null,
                      child: Text(
                        L10n.of(context).lobbyNeedMorePlayers(need),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Cartoon.text(size: 17, color: Colors.white),
                      ),
                    ),
                  );
                }
                final everyoneReady = _allNonHostReady(game);
                // 모두 준비되면 시작 버튼이 숨 쉬듯 움직여 "지금 눌러" 를 알린다.
                final startButton = CartoonButton(
                  height: 56,
                  color: Cartoon.green,
                  onPressed: () => game.startGame(),
                  child: CartoonButton.label(
                    L10n.of(context).lobbyStartGame,
                    size: 22,
                  ),
                );
                return FractionallySizedBox(
                  widthFactor: 0.8,
                  child: everyoneReady
                      ? CartoonPulse(child: startButton)
                      : startButton,
                );
              },
            ),
          ] else
            FractionallySizedBox(
              widthFactor: 0.8,
              child: CartoonButton(
                height: 56,
                // 준비 전엔 노랑(눌러라), 준비하면 초록(됐다).
                color: _isMyReady(game) ? Cartoon.green : Cartoon.yellow,
                onPressed: () => game.toggleReady(),
                child: _isMyReady(game)
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                          const SizedBox(width: 6),
                          CartoonButton.label(
                            L10n.of(context).lobbyReadyDone,
                            size: 20,
                          ),
                        ],
                      )
                    : Text(
                        L10n.of(context).lobbyReady,
                        style: Cartoon.text(size: 22),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// The same draggable panel the game screens use, so chat sits in the same
  /// place and behaves the same way from the waiting room onwards.
  Widget _buildRoomChatPanel(GameService game) {
    _followNewChatMessages(game);
    final accent = _gameAccentColor(game.currentGameType);
    return DraggableChatPanel(
      accentColor: accent,
      sendIconColor: accent,
      title: L10n.of(context).lobbyChat,
      hintText: L10n.of(context).lobbyMessageHint,
      controller: _chatController,
      scrollController: _chatScrollController,
      onSend: () => _sendRoomChatMessage(game),
      onClose: () => setState(() => _roomChatOpen = false),
      onDock: () => _setRoomChatDocked(true, game),
      itemCount: game.chatMessages.length,
      itemBuilder: (context, index) => _buildRoomChatItem(game, index),
      banner: _buildSpectatorStrip(game),
    );
  }

  Widget _buildDockedRoomChat(GameService game) {
    _followNewChatMessages(game);
    final accent = _gameAccentColor(game.currentGameType);
    return DockedChatPanel(
      accentColor: accent,
      sendIconColor: accent,
      title: L10n.of(context).lobbyChat,
      hintText: L10n.of(context).lobbyMessageHint,
      controller: _chatController,
      scrollController: _chatScrollController,
      onSend: () => _sendRoomChatMessage(game),
      onUndock: () => _setRoomChatDocked(false, game),
      onResize: _setDockedChatHeight,
      onResizeEnd: _saveDockedChatHeight,
      itemCount: game.chatMessages.length,
      itemBuilder: (context, index) => _buildRoomChatItem(game, index),
      banner: _buildSpectatorStrip(game),
    );
  }

  /// Who is watching, pinned under the chat header.
  ///
  /// A label and then names, comma-separated and small. A spectator is not at
  /// the table — giving them seats or avatars made the waiting room look like
  /// a ten-player game, which is what the old spectator-only waiting rooms
  /// did. A name is enough to know who is there, and tapping one opens the
  /// same profile popup a seat does.
  ///
  /// A popular room is the case that decides the shape: twenty names would
  /// push the chat off the screen, so the line is cut to a character budget
  /// and the rest becomes "외 N명", which opens the full list. Two lines is
  /// the most this can ever take.
  Widget? _buildSpectatorStrip(GameService game) {
    final watchers = game.spectators;
    if (watchers.isEmpty) return null;
    final names = [
      for (final w in watchers) (w['nickname'] ?? '').toString(),
    ].where((n) => n.isNotEmpty).toList();
    if (names.isEmpty) return null;

    final line = spectatorLine(names);
    final shown = line.shown;
    final hidden = line.hidden;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
      decoration: BoxDecoration(
        color: Cartoon.cream,
        border: Border(
          bottom: BorderSide(
            color: Cartoon.ink.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              L10n.of(context).lobbySpectatorLabel,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: Cartoon.onSurface(const Color(0xFFA1887F)),
              ),
            ),
          ),
          // Separate names rather than one joined string: each has to be
          // tappable on its own. The comma travels with the name before it, so
          // it still reads as one flowing line.
          for (var i = 0; i < shown.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showUserProfileDialog(shown[i], game),
              child: Text(
                '${shown[i]}${i < shown.length - 1 || hidden > 0 ? ', ' : ''}',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: Cartoon.onSurface(const Color(0xFF8A7A72)),
                ),
              ),
            ),
          if (hidden > 0)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showSpectatorListDialog(context, game),
              child: Text(
                L10n.of(context).lobbySpectatorMore(hidden),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: Cartoon.onSurface(const Color(0xFF7E57C2)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Keep the view pinned to the newest message. Called from whichever panel
  /// is on screen; the count guard makes the duplicate call a no-op.
  void _followNewChatMessages(GameService game) {
    if (game.chatMessages.length == _lastChatMessageCount) return;
    _lastChatMessageCount = game.chatMessages.length;
    _scrollChatToBottom();
  }

  /// One message row, newest first (both panels run their list reversed).
  Widget _buildRoomChatItem(GameService game, int index) {
    final msg = game.chatMessages[game.chatMessages.length - 1 - index];
    final sender = msg['sender'] as String? ?? '';
    String message = msg['message'] as String? ?? '';
    if (message == 'chat_banned') {
      final mins = msg['remainingMinutes'] as int? ?? 0;
      message = localizeChatBanned(mins, L10n.of(context));
    }
    final isMe = sender == game.playerName;
    if (sender.isNotEmpty && game.isBlocked(sender)) {
      return const SizedBox.shrink();
    }
    return _buildChatMessage(sender, message, isMe, game);
  }

  /// The colour that game wears everywhere else — the filter chip, the row
  /// strip, the badge. The waiting-room chat was painted Tichu blue whatever
  /// game the room was, so a Skull King room had a bright blue send button
  /// sitting on its navy screen.
  // The palette lives in game_type_icon.dart so the room-creation picker, this
  // screen and the profile popup cannot drift to different colours for the
  // same game — which is exactly what had happened.
  Color _gameAccentColor(String? gameType) => gameTypeColor(gameType ?? '');

  Widget _buildChatMessage(
    String sender,
    String message,
    bool isMe,
    GameService game,
  ) {
    return ChatBubble(
      sender: sender,
      message: message,
      isMe: isMe,
      game: game,
      onTap: sender.isEmpty ? null : () => _showUserProfileDialog(sender, game),
      bottomSpacing: 6,
      avatarRadius: 12,
      avatarBackground: const Color(0xFFE0D8D4),
      senderFontSize: 10,
      messageFontSize: 13,
      bubbleRadius: 12,
      mineColor: _gameAccentColor(game.currentGameType),
      theirsColor: Colors.white,
      theirsBorder: Border.all(color: const Color(0xFFE0D8D4)),
    );
  }

  void _scrollChatToBottom() {
    // ListView is reverse:true so offset 0 == bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.jumpTo(0);
    });
  }

  void _sendRoomChatMessage(GameService game) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    game.sendChatMessage(message);
    _chatController.clear();
    _scrollChatToBottom();
  }

  // Pick + upload a new profile photo for the current user, then surface the
  // outcome. Eligibility (owning an active photo item) is already gated by the
  // caller and re-checked server-side at token issuance.
  /// Blocks the whole screen while the photo is in flight. Deliberately opaque
  /// to touches: a second tap during the upload would burn the one-time token
  /// and start a competing request.
  /// Camera or gallery. Returns null when the sheet is dismissed, which is a
  /// cancel rather than a failure — no snackbar for it.
  // Show user profile dialog with stats.
  // [dialogContext] lets callers (e.g. the Settings screen) open the dialog
  // on top of their own route instead of the lobby — the default falls back
  // to the lobby state's own context.
  void _showUserProfileDialog(
    String nickname,
    GameService game, {
    BuildContext? dialogContext,
  }) {
    showPlayerProfileDialog(
      dialogContext ?? context,
      nickname,
      game,
      subtitle: L10n.of(dialogContext ?? context).lobbyPlayerProfile,
    );
  }

  bool _isMyReady(GameService game) {
    final me = game.roomPlayers.firstWhere(
      (p) => p != null && p.id == game.playerId,
      orElse: () => null,
    );
    return me?.isReady ?? false;
  }

  // Empty (player == null) and not host-blocked → eligible to be filled
  // by the bulk "fill empty seats" button.
  bool _hasFillableEmptySlot(GameService game) {
    for (int i = 0; i < game.roomPlayers.length; i++) {
      if (game.roomPlayers[i] == null && !game.roomBlockedSlots.contains(i)) {
        return true;
      }
    }
    return false;
  }

  // Bulk-fill all eligible empty slots with bots at the given speed. Uses
  // the game-specific default strategy that matches the per-slot popup.
  void _fillEmptySlotsWithBots(GameService game, String speed) {
    final defaultStrategy = game.currentGameType == 'tichu'
        ? BotStrategy.winrate
        : game.currentGameType == 'mighty'
        ? BotStrategy.mixOracle
        : BotStrategy.heuristic;
    for (int i = 0; i < game.roomPlayers.length; i++) {
      if (game.roomPlayers[i] == null && !game.roomBlockedSlots.contains(i)) {
        game.addBot(targetSlot: i, speed: speed, strategy: defaultStrategy);
      }
    }
  }

  Widget _buildFillEmptyBotsRow(GameService game) {
    final l10n = L10n.of(context);
    Widget speedBtn(String speed, IconData icon, Color color, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _fillEmptySlotsWithBots(game, speed),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Cartoon.paper,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Cartoon.ink, width: 1.5),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
          ),
        ),
      );
    }

    // Same surface as the seat rows above it — it used to have its own indigo
    // tint and radius, so the panel read as two different kinds of thing.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: Cartoon.panelDecoration(
        color: Cartoon.surface(Cartoon.surface(const Color(0xFFE9EEFF))),
        radius: 18,
        shadowOffset: 2,
      ),
      child: Row(
        children: [
          Icon(
            Icons.smart_toy_rounded,
            size: 20,
            color: Cartoon.onSurface(const Color(0xFF3949AB)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.lobbyFillEmptyWithBots,
              style: Cartoon.userText(size: 13, weight: FontWeight.w900),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          speedBtn(
            'fast',
            Icons.fast_forward,
            Cartoon.onSurface(const Color(0xFFE65100)),
            l10n.lobbyBotSpeedFast,
          ),
          const SizedBox(width: 6),
          speedBtn(
            'normal',
            Icons.play_arrow,
            Cartoon.onSurface(const Color(0xFF3949AB)),
            l10n.lobbyBotSpeedNormal,
          ),
          const SizedBox(width: 6),
          speedBtn(
            'slow',
            Icons.slow_motion_video,
            Cartoon.onSurface(const Color(0xFF558B2F)),
            l10n.lobbyBotSpeedSlow,
          ),
        ],
      ),
    );
  }

  // True when every seated non-host, non-bot player has toggled ready.
  // Bots count as always-ready; the host is implicitly ready.
  bool _allNonHostReady(GameService game) {
    for (final p in game.roomPlayers) {
      if (p == null) continue;
      if (p.id.startsWith('bot_')) continue;
      if (p.isHost) continue;
      if (!p.isReady) return false;
    }
    return true;
  }

  Widget _buildSkExpansionChip(String expansionKey) {
    final l10n = L10n.of(context);
    // 방 목록 알약과 같은 테마색 바탕에 흰 글자.
    final emoji = _skExpansionEmoji(expansionKey);
    final name = _skExpansionShortLabel(expansionKey, l10n);
    final label = emoji.isEmpty ? name : '$emoji $name';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _skExpansionStrongColor(expansionKey),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Cartoon.ink, width: 1.5),
      ),
      child: Text(
        label,
        style: Cartoon.userText(
          size: 12.5,
          weight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }

  /// Marks the waiting room as one you can be broken into — and walk out of.
  ///
  /// A mark, not a control: the switch lives in the host's room settings. But
  /// everyone at the table needs to see this, because it changes what leaving
  /// means for them (their seat goes to a bot and it is recorded) and what a
  /// missing player means (a bot may quietly take over mid-hand). Same wording
  /// and colours as the badge on the room list, so it reads as the same fact.
  ///
  /// Only rendered when the option is on — there is nothing to say about a
  /// room that behaves the way every other room does.
  Widget _buildMidGameJoinBadge(GameService game) {
    if (!game.roomAllowMidGameJoin) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Cartoon.surface(Cartoon.surface(const Color(0xFFE8E0F8))),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Cartoon.ink, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotSwapIcon(width: 20, height: 16),
          const SizedBox(width: 5),
          Text(
            L10n.of(context).midJoinRoomBadge,
            style: Cartoon.userText(
              size: 12.5,
              weight: FontWeight.w900,
              color: Cartoon.onSurface(const Color(0xFF4A4080)),
            ),
          ),
        ],
      ),
    );
  }

  /// Seating mode: fixed teams vs random teams.
  ///
  /// It used to be one chip showing only the current mode, which reads as a
  /// label — nobody could tell it was a switch, and a non-host who did try got
  /// no response because only the host may change it. Now the host sees both
  /// options with the active one filled, and everyone else sees a plain
  /// read-only chip.
  Widget _buildRandomSeatingChip(GameService game) {
    final on = game.roomRandomSeating;
    final l10n = L10n.of(context);
    final fixedLabel = l10n.lobbyRandomSeatingOff;
    final randomLabel = l10n.lobbyRandomSeatingOn;

    if (!game.isHost) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Cartoon.cream,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Cartoon.ink, width: 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.shuffle : Icons.groups,
              size: 14,
              color: Cartoon.ink,
            ),
            const SizedBox(width: 6),
            Text(
              on ? randomLabel : fixedLabel,
              style: Cartoon.userText(size: 13, weight: FontWeight.w900),
            ),
          ],
        ),
      );
    }

    Widget segment({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: selected ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? Cartoon.orange : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? Cartoon.ink : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? Colors.white : Cartoon.ink,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: Cartoon.userText(
                  size: 13,
                  weight: FontWeight.w900,
                  color: selected ? Colors.white : Cartoon.ink,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Cartoon.cream,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Cartoon.ink, width: 1.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          segment(
            label: fixedLabel,
            icon: Icons.groups,
            selected: !on,
            onTap: () => game.setRandomSeating(false),
          ),
          const SizedBox(width: 2),
          segment(
            label: randomLabel,
            icon: Icons.shuffle,
            selected: on,
            onTap: () => game.setRandomSeating(true),
          ),
        ],
      ),
    );
  }

  Widget _buildClickablePlayerSlot(
    Player? player, {
    required int slotIndex,
    required GameService game,
  }) {
    // Find my current slot
    final myIndex = game.roomPlayers.indexWhere(
      (p) => p != null && p.id == game.playerId,
    );
    final isMySlot = myIndex == slotIndex;
    final isEmpty = player == null;
    final isBot = !isEmpty && player.id.startsWith('bot_');
    final isBlockedPlayer =
        !isEmpty &&
        !isMySlot &&
        !isBot &&
        game.blockedUsers.contains(player.name);
    final isReady = !isEmpty && !isBot && !player.isHost && player.isReady;
    // 이 자리에 깔리는 배너와, 그 위에 올릴 글자색.
    //
    // 전에는 배너가 아래쪽 Builder 안에서만 계산돼서, 글자색 쪽은 서버가
    // 지정한 색(metadata.visual.text.color)만 볼 수 있었다. 그 값이 비면
    // 어두운 배너 위에 어두운 글자가 깔린다. 여기서 한 번 구해 두면 두
    // 곳이 같은 배너를 보고 판단한다.
    final slotBanner = (!isEmpty && !isBot)
        ? game.bannerGradient(player.bannerKey)
        : null;
    final slotBannerOverride = (!isEmpty && !isBot && player.connected)
        ? game.bannerTextColor(player.bannerKey)
        : null;
    final slotHasBanner = slotBanner != null;
    final isSlotBlocked = isEmpty && game.roomBlockedSlots.contains(slotIndex);
    final isFlexibleGame =
        game.currentGameType == 'skull_king' ||
        game.currentGameType == 'love_letter' ||
        game.currentGameType == 'mighty';
    // Host can block empty slots; keep at least the game-specific minimum
    // (Mighty needs 5, SK/LL need 2)
    final minEffective = game.currentGameType == 'mighty' ? 5 : 2;
    final canBlockSlot =
        game.isHost &&
        isEmpty &&
        !isSlotBlocked &&
        isFlexibleGame &&
        (game.roomMaxPlayers - game.roomBlockedSlots.length - 1 >=
            minEffective);
    final canUnblockSlot = game.isHost && isSlotBlocked;
    // Can only move to empty slots (no swapping, no blocked)
    final canMove =
        game.currentGameType != 'skull_king' &&
        !isMySlot &&
        isEmpty &&
        !isSlotBlocked &&
        myIndex != -1;

    return GestureDetector(
      onTap: () {
        // A spectator has no seat to move, so an empty one is an invitation to
        // sit down rather than somewhere to slide across to. Taking it is the
        // same switch_to_player the old spectator waiting room offered, minus
        // the screen it used to live on.
        if (game.isSpectator) {
          if (isEmpty && !isSlotBlocked) {
            game.switchToPlayer(slotIndex);
          } else if (!isEmpty && !isBot) {
            _showUserProfileDialog(player.name, game);
          }
          return;
        }
        if (canUnblockSlot) {
          game.unblockSlot(slotIndex);
        } else if (canMove) {
          // Move to empty slot
          game.changeTeam(slotIndex);
        } else if (!isEmpty && !isBot) {
          // Tapping a filled slot (including my slot): show player profile
          _showUserProfileDialog(player.name, game);
        }
      },
      child: _SeatPop(
        key: ValueKey('${slotIndex}_${player?.id ?? 'empty'}'),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Builder(
              builder: (_) {
                // Equipped banner becomes the slot's background gradient when
                // the player owns one — overrides the state-based pastel fill.
                // The gradient comes from the server's visual catalog so it
                // honors admin-edited angle/stops (not a hardcoded copy).
                final bannerGradient = slotBanner;
                // One neutral fill. Five different tints (ready green, bot indigo,
                // blocked pink, blocked-slot grey, plain beige) made four seats look
                // like four unrelated widgets; ready and "my slot" are already said
                // by the border, and "bot" by the avatar's corner marker.
                // 불투명해야 한다(단색 그림자가 비치지 않게). 빈 자리는 살짝 연한
                // 크림, 막힌 자리는 회색.
                // 자리는 테두리 없이 옅은 바탕만. 내 자리·준비한 자리는 연초록,
                // 빈 자리는 거의 투명하게 두어 "아직 비었다"가 조용히 보인다.
                final fallbackColor = isSlotBlocked
                    ? const Color(0x14000000)
                    : isBlockedPlayer
                    ? Cartoon.surface(const Color(0xFFFAEDED))
                    : isEmpty
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.7);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOut,
                  width: double.infinity,
                  // Sized off the avatar: a 46dp photo with 7 above and below,
                  // which is enough for the level chip that overhangs its bottom
                  // corner by 3. Anything tighter starts clipping the chip
                  // rather than trimming space.
                  //
                  // The side padding is that same 7, so the gap from the avatar
                  // to the box is identical on all four edges. At 8 it wasn't,
                  // and one pixel of difference is visible when the thing it
                  // frames is a square.
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  decoration: BoxDecoration(
                    color: bannerGradient == null ? fallbackColor : null,
                    gradient: bannerGradient,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      // Left-side block X button (host, empty, SK/LL)
                      if (canBlockSlot)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => game.blockSlot(slotIndex),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Cartoon.surface(
                                Cartoon.surface(const Color(0xFFFFE0E0)),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Cartoon.onSurface(const Color(0xFFC62828)),
                            ),
                          ),
                        ),
                      // Blocked slot indicator
                      if (isSlotBlocked)
                        Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Cartoon.onSurface(const Color(0xFF8A7A72)),
                          ),
                        ),
                      // Ready state is now conveyed by the background check
                      // watermark (see Stack below) so the inline check icon is
                      // removed to keep the row layout stable.
                      // Level badge takes the previous host-pill spot. The host
                      // indicator itself is now a 👑 emoji overhanging the top-left
                      // corner (see Positioned below).
                      if (player != null && !isBot)
                        Builder(
                          builder: (_) {
                            // The level badge used to BE the avatar, so a player with a paid
                            // photo showed no level at all, and a photo-less one showed a
                            // brown disc with a number where a face goes. One 38dp avatar —
                            // photo, else a plain silhouette — with the level as a corner
                            // chip, the same shape the bot marker uses. The seat row is 56
                            // tall with no vertical padding.
                            final resolved = game.resolvePhotoUrl(
                              player.photoUrl,
                            );
                            final hidden = game.blockedUsers.contains(
                              player.name,
                            );
                            const avatarSize = 46.0;
                            final avatar = Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Cartoon.ink,
                                  width: 1.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: ProfileAvatar(
                                  photoUrl: resolved,
                                  size: avatarSize - 4,
                                  blocked: hidden,
                                  fallback: DefaultAvatar(size: avatarSize - 4),
                                ),
                              ),
                            );
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: player.level == null
                                  ? avatar
                                  : SizedBox(
                                      width: avatarSize,
                                      height: avatarSize,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          avatar,
                                          Positioned(
                                            right: -3,
                                            bottom: -3,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: Cartoon.paper,
                                                  width: 1.2,
                                                ),
                                              ),
                                              child: LevelBadge(
                                                level: player.level,
                                                size: 14,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            );
                          },
                        ),
                      // Bots have no level and never had a photo, so this slot was empty
                      // for them and every bot row looked alike apart from its number.
                      // Sized like the other games' waiting rooms rather than like the
                      // level badge it sits next to.
                      if (player != null && isBot)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          // The corner marker replaces the "BOT" text chip that used to
                          // sit beside the seat: avatar + chip together left the nickname
                          // no width at all, and it rendered as nothing — so you could
                          // not tell 봇 1 from 봇 2.
                          child: BotAvatar(
                            size: 44,
                            name: player.name,
                            showBadge: true,
                            speed: player.botSpeed,
                          ),
                        ),
                      // Strategy chip only. Speed used to have its own icon here; it is
                      // now the colour of the avatar's corner marker (slow green, normal
                      // blue, fast red), so the icon was saying the same thing twice.
                      if (isBot)
                        Builder(
                          builder: (_) {
                            final strategy = player.botStrategy;
                            final showStrategy =
                                strategy != null &&
                                strategy != BotStrategy.heuristic &&
                                strategy != BotStrategy.winrate &&
                                strategy != BotStrategy.mixOracle &&
                                strategy != BotStrategy.legacyMixExpectimax;
                            if (!showStrategy) return const SizedBox.shrink();
                            return Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC5CAE9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _shortStrategyLabel(strategy),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Cartoon.onSurface(
                                    Cartoon.onSurface(const Color(0xFF6A1B9A)),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      // Blocked indicator
                      if (isBlockedPlayer)
                        Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.block,
                            size: 14,
                            color: Cartoon.onSurface(const Color(0xFFE57373)),
                          ),
                        ),
                      // Bug #8: Disconnected indicator
                      if (player != null && !player.connected)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(
                            Icons.wifi_off,
                            size: 14,
                            color: Color(0xFFFF8A65),
                          ),
                        ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, cons) => FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: cons.maxWidth,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (player != null &&
                                      player.titleName != null)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 2),
                                      child: TitleChip(
                                        titleKey: player.titleKey,
                                        titleName: player.titleName,
                                        // Same override the nickname below uses,
                                        // so both react to a dark banner together.
                                        // 배너가 깔린 자리에서만 그 배너에
                                        // 맞춘다. 배너가 없으면 칩이 제
                                        // 기본색을 쓰게 둔다.
                                        onInk: slotHasBanner
                                            ? profileBannerInk(
                                                slotBanner,
                                                slotBannerOverride,
                                              )
                                            : null,
                                      ),
                                    ),
                                  Builder(
                                    builder: (_) {
                                      // When the slot is showing an equipped banner, prefer the
                                      // banner's admin-defined text color (white-on-galaxy,
                                      // etc.) so the nickname stays readable on dark gradients.
                                      // Falls through to the existing state-based palette for
                                      // empty / bot / blocked / disconnected slots.
                                      // 배너가 깔렸을 때만 배너 쪽 색을
                                      // 쓴다. 봇·차단·연결 끊김은 아래
                                      // 상태색이 뜻을 가지므로 건드리지
                                      // 않는다.
                                      final bannerTextOverride =
                                          (slotHasBanner &&
                                              player != null &&
                                              !isBot &&
                                              player.connected)
                                          ? profileBannerInk(
                                              slotBanner,
                                              slotBannerOverride,
                                            )
                                          : null;
                                      final defaultColor = isBot
                                          ? Cartoon.onSurface(
                                              const Color(0xFF3949AB),
                                            )
                                          : isBlockedPlayer
                                          ? Cartoon.onSurface(
                                              const Color(0xFFBB8888),
                                            )
                                          : (player != null &&
                                                !player.connected)
                                          ? const Color(0xFFBBAAAA)
                                          : player != null
                                          ? Cartoon.ink
                                          : isSlotBlocked
                                          ? Cartoon.onSurface(
                                              const Color(0xFF8A7A72),
                                            )
                                          : Cartoon.ink.withValues(alpha: 0.4);
                                      return Text(
                                        player?.name ??
                                            (isSlotBlocked
                                                ? L10n.of(
                                                    context,
                                                  ).lobbySlotBlocked
                                                : L10n.of(
                                                    context,
                                                  ).lobbyEmptySlot),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color:
                                              bannerTextOverride ??
                                              defaultColor,
                                          fontWeight: isMySlot || player != null
                                              ? FontWeight.w900
                                              : FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 착석. A spectator's way into the game, on the seat
                      // itself rather than as a button somewhere else asking
                      // which seat you meant. Tapping the row does the same
                      // thing; this is the part that says so.
                      if (game.isSpectator && isEmpty && !isSlotBlocked)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => game.switchToPlayer(slotIndex),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: Cartoon.green,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Cartoon.inkOn(Cartoon.green),
                                width: 1.6,
                              ),
                            ),
                            child: Text(
                              L10n.of(context).lobbyTakeSeat,
                              style: Cartoon.text(
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      // Add bot button on empty slots (host only, not ranked, not blocked)
                      if (!game.isSpectator &&
                          isEmpty &&
                          game.isHost &&
                          !game.isRankedRoom &&
                          !isSlotBlocked)
                        PopupMenuButton<String>(
                          onSelected: (speed) {
                            final defaultStrategy =
                                game.currentGameType == 'tichu'
                                ? BotStrategy.winrate
                                : game.currentGameType == 'mighty'
                                ? BotStrategy.mixOracle
                                : BotStrategy.heuristic;
                            game.addBot(
                              targetSlot: slotIndex,
                              speed: speed,
                              strategy: defaultStrategy,
                            );
                          },
                          itemBuilder: (ctx) {
                            final l10n = L10n.of(ctx);
                            return [
                              PopupMenuItem(
                                value: 'fast',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.fast_forward,
                                      size: 16,
                                      color: Cartoon.onSurface(
                                        Cartoon.onSurface(
                                          const Color(0xFFE65100),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        l10n.lobbyBotSpeedFast,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'normal',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.play_arrow,
                                      size: 16,
                                      color: Cartoon.onSurface(
                                        Cartoon.onSurface(
                                          const Color(0xFF3949AB),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        l10n.lobbyBotSpeedNormal,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'slow',
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.slow_motion_video,
                                      size: 16,
                                      color: Cartoon.onSurface(
                                        Cartoon.onSurface(
                                          const Color(0xFF558B2F),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        l10n.lobbyBotSpeedSlow,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ];
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          position: PopupMenuPosition.under,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Cartoon.surface(
                                Cartoon.surface(const Color(0xFFE9EEFF)),
                              ),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(
                                color: Cartoon.ink,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.smart_toy_rounded,
                                  size: 16,
                                  color: Cartoon.onSurface(
                                    Cartoon.onSurface(const Color(0xFF3949AB)),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  L10n.of(context).lobbyBot,
                                  style: Cartoon.userText(
                                    size: 12.5,
                                    weight: FontWeight.w900,
                                    color: Cartoon.onSurface(
                                      Cartoon.onSurface(
                                        const Color(0xFF3949AB),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      // Season rating chip on the right — only in ranked rooms, only
                      // for humans. Number-only, no emoji.
                      if (player != null &&
                          !isBot &&
                          game.isRankedRoom &&
                          player.seasonRating != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Cartoon.surface(
                                Cartoon.surface(const Color(0xFFFFE9B8)),
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Cartoon.ink,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '${player.seasonRating}',
                              style: Cartoon.text(
                                size: 14,
                                color: Cartoon.onSurface(
                                  Cartoon.onSurface(const Color(0xFFB45309)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Kick button: show only for host, on other players' occupied slots (including bots)
                      if (game.isHost && !isEmpty && !isMySlot)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: GestureDetector(
                            onTap: () {
                              if (isBot) {
                                game.kickPlayer(player.id);
                              } else {
                                _showKickConfirmDialog(
                                  player.name,
                                  player.id,
                                  game,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Cartoon.surface(
                                  Cartoon.surface(const Color(0xFFFFE3E3)),
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Cartoon.ink,
                                  width: 1.5,
                                ),
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Cartoon.onSurface(
                                  Cartoon.onSurface(const Color(0xFFC62828)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
            if (isReady)
              Builder(
                builder: (_) {
                  // Same override the nickname/title use — plain green at 18%
                  // reads fine on the default light seat, but disappears against
                  // a dark banner (개천절/크리스마스/한글날 etc). The banner's
                  // own text color is already guaranteed readable against it, so
                  // reuse that instead of a fixed color; bumped up a bit past the
                  // nickname's alpha since a flat white/black watermark is
                  // fainter at a given opacity than the original saturated green.
                  // isReady already implies player != null (isReady's own
                  // definition short-circuits on !isEmpty).
                  // 준비 완료의 초록은 뜻이 있는 색이다. 밝은 배너
                  // 위에서는 그대로 두고, 어두운 배너에서만 읽히게
                  // 바꾼다 — 전부 배너색으로 넘기면 배너를 쓴 사람만
                  // 준비 표시가 초록이 아니게 된다.
                  final onDarkBanner =
                      (!isBot && player.connected) && isDarkBanner(slotBanner);
                  final readyColor = (!isBot && player.connected)
                      ? onBannerAccent(
                          slotBanner,
                          slotBannerOverride,
                          light: Cartoon.onSurface(const Color(0xFF43A047)),
                        )
                      : Cartoon.onSurface(const Color(0xFF43A047));
                  final readyAlpha = onDarkBanner ? 0.3 : 0.4;
                  return Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        // Scaled with the seat (was 56 in a 68-tall row). A
                        // watermark that reaches the edges stops reading as a
                        // background mark.
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.3, end: 1),
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.elasticOut,
                          builder: (_, v, child) =>
                              Transform.scale(scale: v, child: child),
                          child: Icon(
                            Icons.check_circle,
                            size: 48,
                            color: readyColor.withValues(alpha: readyAlpha),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            if (player != null && !isBot && player.isHost)
              const Positioned(
                left: -3,
                top: -7,
                child: CartoonFloat(amplitude: 1.5, child: HostCrown(size: 22)),
              ),
            // What this player just said, for a couple of seconds. Laid over the
            // seat so a line of chat is visible without opening the panel.
            if (player != null) ?_seatChatBubble(player.name),
          ],
        ),
      ),
    );
  }

  String _shortStrategyLabel(String strategy) {
    switch (strategy) {
      case BotStrategy.winrate:
        return 'WR';
      case BotStrategy.pimcPlay:
        return 'PIMC·P';
      case BotStrategy.pimcFull:
        return 'PIMC·F';
      case BotStrategy.expectimax:
        return 'EXMX';
      case BotStrategy.expectimaxSmart:
        return 'EXMX+';
      case BotStrategy.mixOracle:
      case BotStrategy.legacyMixExpectimax:
        return 'MIX';
      default:
        return '';
    }
  }

  void _showKickConfirmDialog(
    String playerName,
    String playerId,
    GameService game,
  ) {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: _dialogTitle(Icons.logout_rounded, Cartoon.red, l10n.lobbyKick),
        content: Text(
          l10n.lobbyKickConfirm(playerName),
          style: Cartoon.userText(size: 16, height: 1.4),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          _dialogPrimary(l10n.lobbyKick, () {
            Navigator.pop(ctx);
            game.kickPlayer(playerId);
          }, color: Cartoon.red),
        ],
      ),
    );
  }
}

/// Full-screen "uploading" barrier, shown as an OverlayEntry above whatever
/// route is current (including the profile dialog).

/// 방 카드의 자리 현황: 앉은 자리는 게임 색으로 채우고 빈 자리는 비워 둔다.
/// 한 자리만 남았으면 그 빈 자리가 깜빡여서 "지금 들어가면 시작" 을 알려 준다.
class _SeatDots extends StatefulWidget {
  const _SeatDots({
    required this.filled,
    required this.total,
    required this.color,
  });

  final int filled;
  final int total;
  final Color color;

  @override
  State<_SeatDots> createState() => _SeatDotsState();
}

class _SeatDotsState extends State<_SeatDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    _syncBlink();
  }

  @override
  void didUpdateWidget(_SeatDots old) {
    super.didUpdateWidget(old);
    _syncBlink();
  }

  void _syncBlink() {
    final lastSeat = widget.total - widget.filled == 1;
    if (lastSeat && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!lastSeat && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.filled >= widget.total;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.total; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                child: _dot(
                  i < widget.filled,
                  blink:
                      i == widget.filled && widget.total - widget.filled == 1,
                  full: full,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _dot(bool filled, {required bool blink, required bool full}) {
    final glow = blink ? _c.value : 0.0;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled
            ? (full ? Cartoon.green : widget.color)
            : Color.lerp(Colors.white, Cartoon.yellow, glow),
        border: Border.all(color: Cartoon.ink, width: 1.4),
        boxShadow: blink
            ? [
                BoxShadow(
                  color: Cartoon.yellow.withValues(alpha: 0.7 * glow),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}

/// 비밀방 자물쇠: 노란 알약 안의 자물쇠가 가끔 달각거린다.
class _LockChip extends StatefulWidget {
  const _LockChip({required this.size});

  final double size;

  @override
  State<_LockChip> createState() => _LockChipState();
}

class _LockChipState extends State<_LockChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        // 앞 20% 에서만 좌우로 달각, 나머지는 가만히.
        final t = (_c.value / 0.2).clamp(0.0, 1.0);
        final angle = _c.value < 0.2
            ? math.sin(t * math.pi * 4) * 0.28 * (1 - t)
            : 0.0;
        return Transform.rotate(angle: angle, child: child);
      },
      child: Container(
        width: s,
        height: s,
        padding: EdgeInsets.all(s * 0.2),
        decoration: BoxDecoration(
          color: Cartoon.yellow,
          borderRadius: BorderRadius.circular(s * 0.34),
          border: Border.all(
            color: Cartoon.inkOn(Cartoon.yellow),
            width: s >= 30 ? 2.5 : 2,
          ),
        ),
        child: LockIcon(width: s * 0.6, height: s * 0.6),
      ),
    );
  }
}

/// 필터 칩과 같은 결의 새로고침 버튼. 누르면 한 바퀴 돈다.
class _RefreshChip extends StatefulWidget {
  const _RefreshChip({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_RefreshChip> createState() => _RefreshChipState();
}

class _RefreshChipState extends State<_RefreshChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CartoonPressable(
      onTap: () {
        _c.forward(from: 0);
        widget.onTap();
      },
      child: Container(
        width: 38,
        height: 34,
        margin: const EdgeInsets.only(bottom: 3, left: 4),
        decoration: BoxDecoration(
          color: Cartoon.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Cartoon.ink, width: 2),
          boxShadow: [BoxShadow(color: Cartoon.ink, offset: Offset(0, 2))],
        ),
        child: RotationTransition(
          turns: CurvedAnimation(parent: _c, curve: Curves.easeInOutCubic),
          child: Icon(Icons.refresh_rounded, color: Cartoon.ink, size: 22),
        ),
      ),
    );
  }
}

/// 자리에 사람이 앉거나 바뀔 때 살짝 커지며 나타난다(key 가 바뀔 때만 재생).
class _SeatPop extends StatelessWidget {
  const _SeatPop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.92 + 0.08 * v, child: child),
      ),
      child: child,
    );
  }
}
