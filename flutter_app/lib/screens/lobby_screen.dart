import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../services/locale_service.dart';
import '../services/session_service.dart';
import '../models/player.dart';
import '../models/room.dart';
import 'ranking_screen.dart';
import 'shop_screen.dart';
import 'settings_screen.dart';
import 'rules_screen.dart';
import 'friends_screen.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/level_badge.dart';
import '../widgets/game_type_icon.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/host_crown.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/title_chip.dart';
import '../services/ad_service.dart';
import '../services/kakao_invite_share_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _inRoom = false;
  bool _roomMoreOpen = false;

  /// Game types the player has switched off in the room list. Empty = show all,
  /// which is the default: you open the lobby to see what is there, not to
  /// configure it first.
  final Set<String> _hiddenGameTypes = {};

  // 채팅
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

  /// Waiting-room chat now opens from the header, like every in-game chat,
  /// instead of living in a panel below the seats that had to be scrolled to.
  bool _roomChatOpen = false;
  int _roomChatRead = 0;

  /// The last thing each player said, shown briefly over their seat so a
  /// message is visible without opening the panel at all.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  // 배너 광고
  BannerAd? _bannerAd;
  bool _bannerAdLoaded = false;
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
    // AdMob has no web implementation at all, so this can only fail there.
    // Leaving it to fail was working — the load callbacks null the banner
    // out — but it is a plugin exception per screen to get to the same
    // place. Web ads would be AdSense / H5 Games Ads, a separate product.
    _bannerAd = kIsWeb
        ? null
        : AdService.createBannerAd(
            AdService.lobbyBannerId,
            onAdLoaded: (_) {
              if (mounted) setState(() => _bannerAdLoaded = true);
            },
            onAdFailedToLoad: (ad, error) {
              ad.dispose();
              if (mounted) {
                setState(() {
                  _bannerAd = null;
                  _bannerAdLoaded = false;
                });
              }
            },
          );
    _bannerAd?.load();
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
      // Auto-show the reply popup once the inquiry list arrives (or already has
      // an unread reply). Listener so it fires when requestInquiries resolves.
      _inquiryGameRef = game;
      game.addListener(_onInquiryUpdate);
      _onInquiryUpdate();
    });
  }

  @override
  void dispose() {
    _inquiryGameRef?.removeListener(_onInquiryUpdate);
    _seatChat.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _bannerAd?.dispose();
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
        game.currentDestination != AppDestination.lobby)
      return;
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
            const Icon(Icons.mark_email_read, color: Color(0xFF1E88E5)),
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
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                adminNote,
                style: const TextStyle(fontSize: 14, color: Color(0xFF5A4038)),
              ),
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

  void _showRoomInviteDialog(Map<String, dynamic> invite, GameService game) {
    final fromNickname = invite['fromNickname'] as String? ?? '';
    final roomName = invite['roomName'] as String? ?? '';
    final isRanked = invite['isRanked'] == true;
    final l10n = L10n.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.mail, color: Color(0xFF7E57C2)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.lobbyRoomInviteTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.lobbyRoomInviteMessage(fromNickname),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF3E5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  if (isRanked)
                    const Text('🏆 ', style: TextStyle(fontSize: 14)),
                  Expanded(
                    child: Text(
                      roomName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.lobbyDecline),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.acceptInvite(invite);
              setState(() => _inRoom = true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7E57C2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(l10n.lobbyJoin),
          ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(Icons.person_add, color: Color(0xFF7E57C2)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    l10n.lobbyInviteFriendsTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: onlineFriends.isEmpty
                ? SizedBox(
                    height: 60,
                    child: Center(
                      child: Text(
                        l10n.lobbyNoOnlineFriends,
                        style: const TextStyle(color: Color(0xFF9A8E8A)),
                      ),
                    ),
                  )
                : SizedBox(
                    width: double.maxFinite,
                    height: 250,
                    child: ListView.separated(
                      itemCount: onlineFriends.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final friend = onlineFriends[index];
                        final nickname = friend['nickname'] as String? ?? '';
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F8E9),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFC8E6C9)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Color(0xFF4CAF50),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  nickname,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF5A4038),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
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
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7E57C2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    l10n.lobbyInvite,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
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

  void _showSpectatorListDialog(GameService game) {
    final spectators = game.spectators;
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.visibility, color: Color(0xFF4A4080)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.lobbySpectatorListTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: spectators.isEmpty
            ? SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    l10n.lobbyNoSpectators,
                    style: const TextStyle(color: Color(0xFF9A8E8A)),
                  ),
                ),
              )
            : SizedBox(
                width: double.maxFinite,
                height: 220,
                child: ListView.separated(
                  itemCount: spectators.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final nickname = spectators[index]['nickname'] ?? '';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDE7F6),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD1C4E9)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 16,
                            color: Color(0xFF6A5A52),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nickname,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF5A4038),
                              ),
                              overflow: TextOverflow.ellipsis,
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
      ),
    );
  }

  void _showRoomSettingsDialog(GameService game) {
    final controller = TextEditingController(text: game.currentRoomName);
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.settings, color: Color(0xFF1E88E5)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.lobbyRoomSettingsTitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: controller,
          maxLength: 20,
          decoration: InputDecoration(
            hintText: l10n.lobbyEnterRoomTitle,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              game.changeRoomName(name);
              Navigator.pop(ctx);
            },
            child: Text(l10n.lobbyChange),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }

  String _generateRandomRoomName({String gameType = 'tichu', L10n? l10n}) {
    final random = DateTime.now().millisecondsSinceEpoch;
    final l = l10n ?? L10n.of(context);
    if (gameType == 'skull_king') {
      final adjectives = [
        l.lobbyRandomAdjSk1,
        l.lobbyRandomAdjSk2,
        l.lobbyRandomAdjSk3,
        l.lobbyRandomAdjSk4,
        l.lobbyRandomAdjSk5,
        l.lobbyRandomAdjSk6,
        l.lobbyRandomAdjSk7,
        l.lobbyRandomAdjSk8,
      ];
      final nouns = [
        l.lobbyRandomNounSk1,
        l.lobbyRandomNounSk2,
        l.lobbyRandomNounSk3,
        l.lobbyRandomNounSk4,
        l.lobbyRandomNounSk5,
        l.lobbyRandomNounSk6,
        l.lobbyRandomNounSk7,
        l.lobbyRandomNounSk8,
      ];
      final adj = adjectives[random % adjectives.length];
      final noun = nouns[(random ~/ 8) % nouns.length];
      return '$adj $noun';
    } else {
      final adjectives = [
        l.lobbyRandomAdjTichu1,
        l.lobbyRandomAdjTichu2,
        l.lobbyRandomAdjTichu3,
        l.lobbyRandomAdjTichu4,
        l.lobbyRandomAdjTichu5,
        l.lobbyRandomAdjTichu6,
        l.lobbyRandomAdjTichu7,
        l.lobbyRandomAdjTichu8,
      ];
      final nouns = [
        l.lobbyRandomNounTichu1,
        l.lobbyRandomNounTichu2,
        l.lobbyRandomNounTichu3,
        l.lobbyRandomNounTichu4,
        l.lobbyRandomNounTichu5,
        l.lobbyRandomNounTichu6,
        l.lobbyRandomNounTichu7,
        l.lobbyRandomNounTichu8,
      ];
      final adj = adjectives[random % adjectives.length];
      final noun = nouns[(random ~/ 8) % nouns.length];
      return '$adj $noun';
    }
  }

  void _showCreateRoomDialog() {
    final l10n = L10n.of(context);
    String randomName = _generateRandomRoomName(l10n: l10n);
    final controller = TextEditingController();
    final passwordController = TextEditingController();
    bool isPrivate = false;
    bool isRanked = false;
    bool allowSpectators = true;
    final timeLimitController = TextEditingController(text: '30');
    final targetScoreController = TextEditingController(text: '1000');
    String selectedGameType = 'tichu';
    bool gamePickerOpen = false;
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
          final fillColor = Colors.white.withValues(alpha: 0.82);

          InputDecoration fieldDecoration(
            String hintText, {
            String? suffixText,
          }) {
            return InputDecoration(
              hintText: hintText,
              suffixText: suffixText,
              filled: true,
              fillColor: fillColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accent, width: 1.4),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            );
          }

          // Title only. Each section also carried a sentence restating what the
          // controls under it obviously do ("플레이할 게임을 선택합니다" over a game
          // picker), which is most of the dialog's height and none of its
          // information. The parameter stays so call sites don't all change.
          Widget sectionTitle(String title, String subtitle) {
            return Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3E312A),
              ),
            );
          }

          Widget optionCard({
            required String title,
            String? description,
            required bool value,
            required ValueChanged<bool> onChanged,
            bool enabled = true,
          }) {
            // A row with a divider, not a card. Each option used to be its own
            // bordered box whose border colour also encoded the value — a card
            // per switch inside a card inside the dialog, saying with a border
            // what the switch already says.
            return Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0x22000000))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: enabled
                                  ? const Color(0xFF4B3C35)
                                  : const Color(0xFF9A8E8A),
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
                                    ? const Color(0xFF7E7069)
                                    : const Color(0xFFAAA09C),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(value: value, onChanged: enabled ? onChanged : null),
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
                ),
                backgroundColor: themeColors.first.withValues(alpha: 0.94),
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
                              Builder(
                                builder: (ctx) {
                                  String gameLabel;
                                  Color gameBgColor;
                                  Color gameFgColor;
                                  // Same colours as the room list's strips, badges
                                  // and filters — the dialog had its own palette
                                  // (purple Tichu, yellow-on-navy SK) so the same game
                                  // wore different colours two screens apart.
                                  switch (selectedGameType) {
                                    case 'skull_king':
                                      gameLabel = l10n.lobbySkullKing;
                                      gameBgColor = const Color(0xFF21455F);
                                      gameFgColor = Colors.white;
                                      break;
                                    case 'love_letter':
                                      gameLabel = l10n.lobbyLoveLetter;
                                      gameBgColor = const Color(0xFFE91E63);
                                      gameFgColor = Colors.white;
                                      break;
                                    case 'mighty':
                                      gameLabel = l10n.lobbyMighty;
                                      gameBgColor = const Color(0xFF5C6BC0);
                                      gameFgColor = Colors.white;
                                      break;
                                    default:
                                      gameLabel = l10n.lobbyTichu;
                                      gameBgColor = const Color(0xFF64B5F6);
                                      gameFgColor = Colors.white;
                                  }
                                  return Column(
                                    children: [
                                      InkWell(
                                        onTap: () => setState(
                                          () =>
                                              gamePickerOpen = !gamePickerOpen,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: gameBgColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                gameTypeIcon(selectedGameType),
                                                size: 18,
                                                color: gameFgColor,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  gameLabel,
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                    color: gameFgColor,
                                                  ),
                                                ),
                                              ),
                                              AnimatedRotation(
                                                turns: gamePickerOpen ? 0.5 : 0,
                                                duration: const Duration(
                                                  milliseconds: 160,
                                                ),
                                                child: Icon(
                                                  Icons.arrow_drop_down,
                                                  color: gameFgColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
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
                                    ].indexed) ...[
                                      if (i > 0) const SizedBox(width: 6),
                                      Expanded(
                                        child: Builder(
                                          builder: (_) {
                                            final selected =
                                                skExpansionsSelected.contains(
                                                  entry[0],
                                                );
                                            return GestureDetector(
                                              behavior: HitTestBehavior.opaque,
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
                                                  // Solid brown, not the theme accent:
                                                  // the accent is a pale peach and a
                                                  // pale fill did not read as "on".
                                                  color: selected
                                                      ? const Color(0xFF6A5A52)
                                                      : Colors.white.withValues(
                                                          alpha: 0.82,
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  border: Border.all(
                                                    color: selected
                                                        ? const Color(
                                                            0xFF6A5A52,
                                                          )
                                                        : const Color(
                                                            0xFFE0D5D0,
                                                          ),
                                                  ),
                                                ),
                                                child: Column(
                                                  children: [
                                                    Text(
                                                      entry[1],
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: selected
                                                            ? Colors.white
                                                            : const Color(
                                                                0xFF8A7A72,
                                                              ),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      entry[2],
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: selected
                                                            ? Colors.white
                                                                  .withValues(
                                                                    alpha: 0.85,
                                                                  )
                                                            : const Color(
                                                                0xFFAAA09C,
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
                                        child: const Icon(
                                          Icons.casino,
                                          size: 20,
                                          color: Color(0xFF6A5A52),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              optionCard(
                                title: l10n.lobbyPrivateRoom,
                                description: isRanked
                                    ? l10n.lobbyPrivateRoomDescRanked
                                    : null,
                                value: isPrivate,
                                enabled: !isRanked,
                                onChanged: (v) => setState(() => isPrivate = v),
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
                                title: l10n.lobbyAllowSpectators,
                                value: allowSpectators,
                                onChanged: (v) =>
                                    setState(() => allowSpectators = v),
                              ),
                              if (selectedGameType != 'love_letter' &&
                                  context.read<GameService>().authProvider !=
                                      'local') ...[
                                optionCard(
                                  title: l10n.lobbyRanked,
                                  description: selectedGameType == 'skull_king'
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
                                          controller: timeLimitController,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(3),
                                          ],
                                          textAlign: TextAlign.center,
                                          decoration: fieldDecoration(
                                            l10n.lobbyTimeLimitRange,
                                            suffixText: l10n.lobbySuffixSeconds,
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
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          TextField(
                                            controller: targetScoreController,
                                            enabled: !isRanked,
                                            keyboardType: TextInputType.number,
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
                                              suffixText:
                                                  l10n.lobbySuffixPoints,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
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
                                    color: const Color(0xFFFFECEC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFF2B3B3),
                                    ),
                                  ),
                                  child: Text(
                                    errorText!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFB54A4A),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (gamePickerOpen)
                            Positioned(
                              top: 52,
                              left: 0,
                              right: 0,
                              child: Material(
                                color: Colors.transparent,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE0D5D0),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.14,
                                        ),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (final (type, label, color) in [
                                        (
                                          'tichu',
                                          l10n.lobbyTichu,
                                          const Color(0xFF64B5F6),
                                        ),
                                        (
                                          'mighty',
                                          l10n.lobbyMighty,
                                          const Color(0xFF5C6BC0),
                                        ),
                                        (
                                          'skull_king',
                                          l10n.lobbySkullKing,
                                          const Color(0xFF21455F),
                                        ),
                                        (
                                          'love_letter',
                                          l10n.lobbyLoveLetter,
                                          const Color(0xFFE91E63),
                                        ),
                                      ])
                                        InkWell(
                                          onTap: () {
                                            selectGame(type);
                                            setState(
                                              () => gamePickerOpen = false,
                                            );
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  gameTypeIcon(type),
                                                  size: 16,
                                                  color: color,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    label,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: color,
                                                    ),
                                                  ),
                                                ),
                                                if (selectedGameType == type)
                                                  Icon(
                                                    Icons.check,
                                                    size: 18,
                                                    color: color,
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
                      );
                      Navigator.pop(context);
                      setState(() => _inRoom = true);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: const Color(0xFF2A1E18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
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
    // Same call the game screen makes: the landscape variants are built for a
    // tablet held sideways, and the app no longer rotates at all, so on the web
    // they are the only place that code runs — untested by everyone else. It
    // shows: the landscape lobby packs notices and errors into a bordered
    // utility box, which is not how the app has ever presented them.
    final isLandscape =
        !kIsWeb && MediaQuery.of(context).orientation == Orientation.landscape;
    return ConnectionOverlay(
      child: PopScope(
        canPop: false,
        child: Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: themeColors,
              ),
            ),
            child: SafeArea(
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
                          backgroundColor: Colors.red,
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
                  if (game.isInWaitingRoom && !_inRoom) {
                    _inRoom = true;
                  }

                  final destination = game.currentDestination;

                  if (destination != AppDestination.lobby || _inRoom) {
                    _inRoom = true;
                    return _buildRoomView(game, isLandscape: isLandscape);
                  }
                  return _buildLobbyView(game, isLandscape: isLandscape);
                },
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

    // Single shared banner-ad slot (same tree position for both orientations)
    // so the one BannerAd is never attached to two AdWidgets at once — which
    // throws "AdWidget is already in the Widget tree" during an orientation /
    // rebuild transition.
    return Column(
      children: [
        Expanded(child: body),
        if (_bannerAd != null && _bannerAdLoaded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: SizedBox(
                height: _bannerAd!.size.height.toDouble(),
                width: _bannerAd!.size.width.toDouble(),
                child: AdWidget(
                  ad: _bannerAd!,
                  key: ValueKey(_bannerAd!.hashCode),
                ),
              ),
            ),
          ),
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
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9DED9)),
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 14 : 16,
        vertical: isLandscape ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
      ),
      margin: EdgeInsets.all(isLandscape ? 12 : 16),
      clipBehavior: Clip.none,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: isLandscape ? 36 : 44),
            child: Image.asset('assets/logo2.webp', fit: BoxFit.contain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: _buildLobbyActionButtons(game),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildLobbyActionButtons(GameService game) {
    final attendance = game.attendanceState;
    // Never on the web: the attendance banner inside the shop is hidden there
    // (the daily reward needs a rewarded ad, and AdMob has no web build), so a
    // dot pointing at it would send players to a screen with nothing to claim.
    // Same condition as _shouldShowAttendanceBanner in shop_screen.
    final attendanceUnclaimed = !kIsWeb &&
        attendance != null &&
        attendance['claimedToday'] != true;
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
          ),
          if (attendanceUnclaimed)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
      Stack(
        children: [
          _buildIconButton(
            icon: Icons.people,
            color: const Color(0xFF7E57C2),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FriendsScreen()),
              );
            },
          ),
          if ((game.pendingFriendRequestCount + game.totalUnreadDmCount) > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
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
      ),
      _buildIconButton(
        icon: Icons.menu_book_rounded,
        color: const Color(0xFFFF8A65),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RulesScreen()),
          );
        },
      ),
      Stack(
        clipBehavior: Clip.none,
        children: [
          _buildIconButton(
            icon: Icons.settings,
            color: const Color(0xFF9E9E9E),
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
          ),
          // Badge covers BOTH unread notices and unread inquiry replies, so an
          // answered inquiry is discoverable on the room-list page (settings →
          // 문의내역) instead of relying on the transient banner.
          if (game.unreadNoticeCount + game.unreadInquiryReplyCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                child: Text(
                  (game.unreadNoticeCount + game.unreadInquiryReplyCount) > 9
                      ? '9+'
                      : '${game.unreadNoticeCount + game.unreadInquiryReplyCount}',
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
        color: const Color(0xFFDEDBFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF9A8FE8)),
      ),
      child: Row(
        children: [
          // Not a spinner: nothing is loading here and the wait is on the
          // other server finishing its round. This says "your game is being
          // moved here", which is what is actually happening.
          const Icon(
            Icons.swap_horiz_rounded,
            size: 20,
            color: Color(0xFF4A4080),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              L10n.of(context).lobbyMatchIncoming,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4A4080),
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3E0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFB74D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.construction, color: Color(0xFFE65100), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.maintenanceMessage.isNotEmpty
                      ? game.maintenanceMessage
                      : L10n.of(context).lobbyMaintenanceDefault,
                  style: const TextStyle(
                    color: Color(0xFFE65100),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (timeText.isNotEmpty)
                  Text(
                    timeText,
                    style: const TextStyle(
                      color: Color(0xFFBF360C),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInquiryBanner(GameService game) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mark_email_read, color: Color(0xFF1E88E5), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              localizeInquiryBanner(
                game.inquiryBannerMessage,
                L10n.of(context),
              ),
              style: const TextStyle(
                color: Color(0xFF1E88E5),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: () => game.requestInquiries(),
            child: const Icon(
              Icons.refresh,
              size: 18,
              color: Color(0xFF1E88E5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF9A9A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning, color: Color(0xFFC62828), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              localizeServiceMessage(message, L10n.of(context)),
              style: const TextStyle(
                color: Color(0xFFC62828),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
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
                  child: Row(children: _buildGameFilterChips()),
                ),
              ),
              IconButton(
                onPressed: () {
                  game.requestRoomList();
                },
                icon: const Icon(Icons.refresh),
                color: const Color(0xFF8A7A72),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
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
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _showCreateRoomDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC7E6D0),
                foregroundColor: const Color(0xFF3A5A40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: 0,
              ),
              child: Text(
                L10n.of(context).lobbyCreateRoom,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
      const Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(color: Color(0xFF8A7A72)),
      ),
    );
  }

  Widget _buildEmptyRoomList() {
    return _fillScrollable(
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.meeting_room_outlined,
              size: 48,
              color: Color(0xFFC4B8B0),
            ),
            const SizedBox(height: 12),
            Text(
              L10n.of(context).lobbyEmptyRoomList,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF9A8E8A)),
            ),
          ],
        ),
      ),
    );
  }

  /// One toggle per game type. Coloured while its rooms are showing, drained
  /// when they are hidden — the colour matches that game's strip and badge in the
  /// rows below, so the filter and the thing it filters read as the same family.
  List<Widget> _buildGameFilterChips() {
    final l10n = L10n.of(context);
    final games = [
      ('tichu', l10n.lobbyTichu, const Color(0xFF64B5F6)),
      ('mighty', l10n.rankingMighty, const Color(0xFF5C6BC0)),
      ('skull_king', l10n.lobbySkullKing, const Color(0xFF21455F)),
      ('love_letter', l10n.lobbyLoveLetter, const Color(0xFFE91E63)),
    ];
    return [
      for (final (type, label, color) in games)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() {
              if (_hiddenGameTypes.remove(type)) return;
              // The last one on stays on. Turning everything off leaves a list
              // that can only ever be empty, which is not a state anyone wants
              // to arrive at by tapping.
              if (_hiddenGameTypes.length < games.length - 1) {
                _hiddenGameTypes.add(type);
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _hiddenGameTypes.contains(type)
                    ? Colors.white.withValues(alpha: 0.6)
                    : color,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _hiddenGameTypes.contains(type)
                      ? const Color(0xFFE6DDD8)
                      : color,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _hiddenGameTypes.contains(type)
                      ? const Color(0xFFB4A8A2)
                      : Colors.white,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildRoomList(List<Room> allRooms) {
    final rooms = _hiddenGameTypes.isEmpty
        ? allRooms
        : allRooms
              .where((r) => !_hiddenGameTypes.contains(r.gameType))
              .toList();
    if (rooms.isEmpty) {
      return Center(
        child: Text(
          L10n.of(context).lobbyNoRoomsForFilter,
          style: const TextStyle(color: Color(0xFF9C8B84)),
          textAlign: TextAlign.center,
        ),
      );
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
      itemCount: sorted.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final room = sorted[index];
        return _buildRoomItem(room);
      },
    );
  }

  String _skExpansionShortLabel(String expansionId, L10n l10n) {
    switch (expansionId) {
      case 'kraken':
        return l10n.lobbyExpKrakenShort;
      case 'white_whale':
        return l10n.lobbyExpWhaleShort;
      case 'loot':
        return l10n.lobbyExpLootShort;
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

    if (isLL) {
      stripColor = const Color(0xFFE91E63);
      badgeBgColor = const Color(0xFFE91E63);
      badgeText = l10n.lobbyLoveLetterBadge;
    } else if (isMighty) {
      stripColor = const Color(0xFF5C6BC0);
      badgeBgColor = const Color(0xFF5C6BC0);
      badgeText = l10n.lobbyMightyBadge;
    } else if (isSK) {
      stripColor = const Color(0xFF21455F);
      badgeBgColor = const Color(0xFF21455F);
      badgeText = l10n.lobbySkullKingBadge;
    } else {
      stripColor = const Color(0xFF64B5F6);
      badgeBgColor = const Color(0xFF64B5F6);
      badgeText = l10n.lobbyTichuBadge;
    }
    const nameColor = Color(0xFF4E3A34);
    const subTextColor = Color(0xFF9C8B84);

    return Material(
      color: Colors.white.withValues(alpha: 0.72),
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
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE6DDD8)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left color strip — stretches to cell height.
                Container(
                  width: 6,
                  decoration: BoxDecoration(
                    color: stripColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      bottomLeft: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
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
                                      horizontal: 7,
                                      vertical: 3,
                                    ),
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: badgeBgColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      badgeText,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: badgeTextColor,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${room.isPrivate ? '🔒 ' : ''}${room.isRanked ? '🏆 ' : ''}${room.name}',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: nameColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(right: 2),
                                    child: Text(
                                      (isSK || isLL)
                                          ? l10n.lobbyRoomTimeSec(
                                              room.turnTimeLimit,
                                            )
                                          : l10n.lobbyRoomTimeAndScore(
                                              room.turnTimeLimit,
                                              room.targetScore,
                                            ),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: subTextColor,
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
                                          color: const Color(0xFF2D2D3D),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          border: Border.all(
                                            color: const Color(
                                              0xFFFFD54F,
                                            ).withValues(alpha: 0.5),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          _skExpansionShortLabel(exp, l10n),
                                          style: const TextStyle(
                                            fontSize: 9,
                                            color: Color(0xFFFFD54F),
                                            fontWeight: FontWeight.bold,
                                            height: 1.0,
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
                        if (isInProgress)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0EBE8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              l10n.lobbyRoomPlaying,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A7A72),
                              ),
                            ),
                          ),
                        if (room.allowSpectators)
                          GestureDetector(
                            onTap: () => _spectateWithPasswordCheck(room),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 7,
                              ),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFE6DDD8),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.visibility,
                                    size: 16,
                                    color: Color(0xFF7A6A62),
                                  ),
                                  if (room.spectatorCount > 0) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      '${room.spectatorCount}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF7A6A62),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F3F2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${room.playerCount}/${room.effectiveMaxPlayers}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              // Same reading as the waiting room's header: green
                              // when there is no seat left, amber while there is.
                              color:
                                  room.playerCount >= room.effectiveMaxPlayers
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFFF9800),
                            ),
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
    );
  }

  void _showRankedSocialRequiredDialog() {
    final l10n = L10n.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.lock, color: Color(0xFFF2A65A), size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.lobbySocialLinkRequired,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Text(
          l10n.lobbySocialLinkRequiredDesc,
          style: const TextStyle(fontSize: 14, color: Color(0xFF5A4038)),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: l10n.lobbyPassword),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              final password = controller.text.trim();
              if (password.isEmpty) return;
              Navigator.pop(ctx);
              onSubmit(password);
            },
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomView(GameService game, {required bool isLandscape}) {
    final isKoreanUser =
        context.read<LocaleService>().effectiveLocale.languageCode == 'ko';
    _seatChat.consume(game);
    if (_roomChatOpen) _roomChatRead = game.chatMessages.length;
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

              // Scrollable content area
              // Chat is a header button and an overlay panel now, the same as every
              // in-game chat — it used to sit under the seats, so reading it meant
              // scrolling past the whole room first.
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: _buildRoomPlayersPanel(game),
                ),
              ),
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
          if (_roomChatOpen) _buildRoomChatPanel(game),
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
                    color: const Color(0xFFD8CEC8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.lobbyShareSheetTitle,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4E342E),
                ),
              ),
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
          color: const Color(0xFFF6F3F2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: const Color(0xFF8A7A72)),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF4E342E),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF8A7A72)),
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
        child: SeatChatBubble(text: text),
      ),
    );
  }

  Widget _roomIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool active = false,
    int badge = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF6A5A52) : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active
                    ? const Color(0xFF6A5A52)
                    : const Color(0xFFE6DDD8),
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: active ? Colors.white : const Color(0xFF7A6A62),
            ),
          ),
          if (badge > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
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
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
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
                // Changes what YOU are in the room.
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
                  onTap: () => _showSpectatorListDialog(game),
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
                      color: const Color(0xFFF6F3F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 19, color: const Color(0xFF6A5A52)),
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
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Colors.white, width: 1.2),
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
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A7A72),
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
      padding: EdgeInsets.fromLTRB(
        8,
        isLandscape ? 6 : 8,
        12,
        isLandscape ? 6 : 8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFDFBFA),
        border: Border(bottom: BorderSide(color: Color(0xFFEDE4E0))),
      ),
      // One row: back, a title block (room name + its rules underneath), then
      // icon-only actions. It was two rows — title with two chips and a share
      // button, then four labelled pastel chips — which spent ~110dp of height
      // and still truncated the room name. Labels moved into the icons' own
      // affordance; switch-to-spectator moved into the ⋯ sheet.
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              game.leaveRoom();
              setState(() => _inRoom = false);
              // No immediate re-check here: _inRoom flips to false before the
              // server confirms, so the strengthened _onInquiryUpdate guard
              // would defer anyway. The server-confirm notify re-fires the
              // listener once truly on the lobby.
            },
            icon: const Icon(Icons.arrow_back),
            color: const Color(0xFF8A7A72),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Builder(
              builder: (_) {
                final isSeatCounted =
                    game.currentGameType == 'skull_king' ||
                    game.currentGameType == 'love_letter';
                final full = game.playerCount >= game.effectiveRoomMaxPlayers;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.currentRoomName,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF4E3A34),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isSeatCounted
                                ? L10n.of(context).lobbyRoomInfoSk(
                                    game.roomTurnTimeLimit,
                                    game.playerCount,
                                    game.effectiveRoomMaxPlayers,
                                  )
                                : L10n.of(context).lobbyRoomInfoTichu(
                                    game.roomTurnTimeLimit,
                                    game.roomTargetScore,
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF9C8B84),
                            ),
                          ),
                        ),
                        // The SK/LL string already carries the seat count.
                        if (!isSeatCounted) ...[
                          const Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFC4B8B2),
                            ),
                          ),
                          Text(
                            '${game.playerCount}/${game.effectiveRoomMaxPlayers}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: full
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFFF9800),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          _roomIconButton(
            icon: Icons.chat_bubble_outline,
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

  Widget _buildRoomPlayersPanel(GameService game) {
    // No card of its own: the seat rows inside already carry their own fills,
    // and wrapping them in a white panel on a tinted page just added a border to
    // look past.
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          if (game.isRankedRoom) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏆', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    game.currentGameType == 'skull_king'
                        ? L10n.of(context).lobbySkullKingRanked
                        : game.currentGameType == 'mighty'
                        ? L10n.of(context).lobbyMightyRanked
                        : L10n.of(context).lobbyTichuRanked,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < game.roomPlayers.length; i++) ...[
              _buildClickablePlayerSlot(
                game.roomPlayers[i],
                slotIndex: i,
                game: game,
              ),
              if (i < game.roomPlayers.length - 1) const SizedBox(height: 8),
            ],
          ] else if (game.currentGameType == 'skull_king' ||
              game.currentGameType == 'love_letter' ||
              game.currentGameType == 'mighty') ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: game.currentGameType == 'love_letter'
                    ? const Color(0xFF8B1A1A)
                    : game.currentGameType == 'mighty'
                    ? const Color(0xFF1565C0)
                    : const Color(0xFF2D2D3D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    game.currentGameType == 'love_letter'
                        ? Icons.favorite
                        : game.currentGameType == 'mighty'
                        ? Icons.style
                        : Icons.anchor,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    game.currentGameType == 'love_letter'
                        ? L10n.of(
                            context,
                          ).lobbyLoveLetterPlayers(game.roomMaxPlayers)
                        : game.currentGameType == 'mighty'
                        ? 'Mighty ${game.playerCount}/${game.effectiveRoomMaxPlayers}'
                        : L10n.of(
                            context,
                          ).lobbySkullKingPlayers(game.roomMaxPlayers),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
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
            const SizedBox(height: 12),
            for (int i = 0; i < game.roomPlayers.length; i++) ...[
              _buildClickablePlayerSlot(
                game.roomPlayers[i],
                slotIndex: i,
                game: game,
              ),
              if (i < game.roomPlayers.length - 1) const SizedBox(height: 8),
            ],
          ] else ...[
            // Compact random-team chip for non-ranked Tichu. Host taps to
            // toggle; non-hosts see the current state as read-only.
            if (game.currentGameType == 'tichu' && !game.isRankedRoom) ...[
              _buildRandomSeatingChip(game),
              const SizedBox(height: 12),
            ],
            if (game.roomRandomSeating) ...[
              for (int i = 0; i < game.roomPlayers.length; i++) ...[
                _buildClickablePlayerSlot(
                  game.roomPlayers[i],
                  slotIndex: i,
                  game: game,
                ),
                if (i < game.roomPlayers.length - 1) const SizedBox(height: 8),
              ],
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'TEAM A',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF6A9BD1),
                          ),
                        ),
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
                        const Text(
                          'TEAM B',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF5B8C0),
                          ),
                        ),
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
          if (game.isHost) ...[
            Builder(
              builder: (_) {
                final canStart =
                    game.currentGameType == 'skull_king' ||
                        game.currentGameType == 'love_letter'
                    ? game.playerCount >= 2
                    : game.currentGameType == 'mighty'
                    ? game.playerCount >= 5
                    : game.playerCount >= game.effectiveRoomMaxPlayers;
                if (!canStart) return const SizedBox.shrink();
                final everyoneReady = _allNonHostReady(game);
                return FractionallySizedBox(
                  widthFactor: 2 / 3,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => game.startGame(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFDEDBFA),
                        foregroundColor: const Color(0xFF4A4080),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: everyoneReady
                              ? const BorderSide(
                                  color: Color(0xFF6C63FF),
                                  width: 2.5,
                                )
                              : BorderSide.none,
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        L10n.of(context).lobbyStartGame,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ] else
            FractionallySizedBox(
              widthFactor: 2 / 3,
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => game.toggleReady(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isMyReady(game)
                        ? const Color(0xFFC8E6C9)
                        : const Color(0xFFFFE082),
                    foregroundColor: _isMyReady(game)
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFF5A4038),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      // Border only on ready — not-ready stays borderless so
                      // it doesn't compete with host's start-game emphasis.
                      side: _isMyReady(game)
                          ? const BorderSide(
                              color: Color(0xFF43A047),
                              width: 2.5,
                            )
                          : BorderSide.none,
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isMyReady(game)
                        ? L10n.of(context).lobbyReadyDone
                        : L10n.of(context).lobbyReady,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      _scrollChatToBottom();
    }
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
      itemCount: game.chatMessages.length,
      itemBuilder: (context, index) {
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
      },
    );
  }

  /// The colour that game wears everywhere else — the filter chip, the row
  /// strip, the badge. The waiting-room chat was painted Tichu blue whatever
  /// game the room was, so a Skull King room had a bright blue send button
  /// sitting on its navy screen.
  Color _gameAccentColor(String? gameType) {
    switch (gameType) {
      case 'love_letter':
        return const Color(0xFFE91E63);
      case 'mighty':
        return const Color(0xFF5C6BC0);
      case 'skull_king':
        return const Color(0xFF21455F);
      default:
        return const Color(0xFF64B5F6);
    }
  }

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
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      );
    }

    // Same surface as the seat rows above it — it used to have its own indigo
    // tint and radius, so the panel read as two different kinds of thing.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6DDD8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.smart_toy, size: 16, color: Color(0xFF7A6A62)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              l10n.lobbyFillEmptyWithBots,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3949AB),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          speedBtn(
            'fast',
            Icons.fast_forward,
            const Color(0xFFE65100),
            l10n.lobbyBotSpeedFast,
          ),
          const SizedBox(width: 6),
          speedBtn(
            'normal',
            Icons.play_arrow,
            const Color(0xFF3949AB),
            l10n.lobbyBotSpeedNormal,
          ),
          const SizedBox(width: 6),
          speedBtn(
            'slow',
            Icons.slow_motion_video,
            const Color(0xFF558B2F),
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
    String label;
    Color fg;
    Color bg;
    switch (expansionKey) {
      case 'kraken':
        label = '🐙 ${l10n.lobbyExpKrakenShort}';
        fg = const Color(0xFF6A1B9A);
        bg = const Color(0xFFF3E5F5);
        break;
      case 'white_whale':
        label = '🐳 ${l10n.lobbyExpWhaleShort}';
        fg = const Color(0xFF01579B);
        bg = const Color(0xFFE1F5FE);
        break;
      case 'loot':
        label = '💰 ${l10n.lobbyExpLootShort}';
        fg = const Color(0xFFBF7100);
        bg = const Color(0xFFFFF3E0);
        break;
      default:
        label = expansionKey;
        fg = const Color(0xFF5A4038);
        bg = const Color(0xFFEFEBE9);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg),
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
          color: const Color(0xFFF6F3F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              on ? Icons.shuffle : Icons.groups,
              size: 14,
              color: const Color(0xFF9C8B84),
            ),
            const SizedBox(width: 6),
            Text(
              on ? randomLabel : fixedLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A7A72),
              ),
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
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected
                    ? const Color(0xFF6A5A52)
                    : const Color(0xFFA89C96),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? const Color(0xFF5A4038)
                      : const Color(0xFFA89C96),
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
        color: const Color(0xFFF0EBE8),
        borderRadius: BorderRadius.circular(13),
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
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Builder(
            builder: (_) {
              // Equipped banner becomes the slot's background gradient when
              // the player owns one — overrides the state-based pastel fill.
              // The gradient comes from the server's visual catalog so it
              // honors admin-edited angle/stops (not a hardcoded copy).
              final bannerGradient = (!isEmpty && !isBot)
                  ? game.bannerGradient(player.bannerKey)
                  : null;
              // One neutral fill. Five different tints (ready green, bot indigo,
              // blocked pink, blocked-slot grey, plain beige) made four seats look
              // like four unrelated widgets; ready and "my slot" are already said
              // by the border, and "bot" by the avatar's corner marker.
              final fallbackColor = isSlotBlocked
                  ? const Color(0xFFEFEBE9)
                  : isBlockedPlayer
                  ? const Color(0xFFFAF3F3)
                  : Colors.white.withValues(alpha: 0.72);
              return Container(
                width: double.infinity,
                // Grows with the avatar: 46dp photo + the corner level chip.
                height: 68,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: bannerGradient == null ? fallbackColor : null,
                  gradient: bannerGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    // "My slot" is now indicated by a thicker brown-green
                    // border instead of a tinted background, so the banner
                    // gradient stays visible.
                    color: isSlotBlocked
                        ? const Color(0xFFCFC7C0)
                        : (isMySlot || isReady)
                        ? const Color(0xFF66BB6A)
                        : const Color(0xFFE6DDD8),
                    width: (isMySlot || isReady) ? 2 : 1,
                  ),
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
                            color: const Color(0xFFFFE0E0),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Color(0xFFC62828),
                          ),
                        ),
                      ),
                    // Blocked slot indicator
                    if (isSlotBlocked)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: Color(0xFF8A7A72),
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
                          final avatar = ProfileAvatar(
                            photoUrl: resolved,
                            size: avatarSize,
                            blocked: hidden,
                            fallback: Container(
                              width: avatarSize,
                              height: avatarSize,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF0E7E3),
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.person,
                                size: 27,
                                color: Color(0xFF9C8B84),
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
                                                color: Colors.white,
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
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6A1B9A),
                              ),
                            ),
                          );
                        },
                      ),
                    // Blocked indicator
                    if (isBlockedPlayer)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.block,
                          size: 14,
                          color: Color(0xFFE57373),
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
                                if (player != null && player.titleName != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: TitleChip(
                                      titleKey: player.titleKey,
                                      titleName: player.titleName,
                                    ),
                                  ),
                                Builder(
                                  builder: (_) {
                                    // When the slot is showing an equipped banner, prefer the
                                    // banner's admin-defined text color (white-on-galaxy,
                                    // etc.) so the nickname stays readable on dark gradients.
                                    // Falls through to the existing state-based palette for
                                    // empty / bot / blocked / disconnected slots.
                                    final bannerTextOverride =
                                        (player != null &&
                                            !isBot &&
                                            player.connected)
                                        ? game.bannerTextColor(player.bannerKey)
                                        : null;
                                    final defaultColor = isBot
                                        ? const Color(0xFF3949AB)
                                        : isBlockedPlayer
                                        ? const Color(0xFFBB8888)
                                        : (player != null && !player.connected)
                                        ? const Color(0xFFBBAAAA)
                                        : player != null
                                        ? const Color(0xFF5A4038)
                                        : isSlotBlocked
                                        ? const Color(0xFF8A7A72)
                                        : const Color(0xFFAA9A92);
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
                                            bannerTextOverride ?? defaultColor,
                                        fontWeight: isMySlot
                                            ? FontWeight.bold
                                            : FontWeight.normal,
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
                    // Add bot button on empty slots (host only, not ranked, not blocked)
                    if (isEmpty &&
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
                                  const Icon(
                                    Icons.fast_forward,
                                    size: 16,
                                    color: Color(0xFFE65100),
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
                                  const Icon(
                                    Icons.play_arrow,
                                    size: 16,
                                    color: Color(0xFF3949AB),
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
                                  const Icon(
                                    Icons.slow_motion_video,
                                    size: 16,
                                    color: Color(0xFF558B2F),
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
                            color: const Color(0xFFE8EAF6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.smart_toy,
                                size: 14,
                                color: Color(0xFF3949AB),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                L10n.of(context).lobbyBot,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF3949AB),
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
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFFE0B2)),
                          ),
                          child: Text(
                            '${player.seasonRating}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE65100),
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
                              color: const Color(0xFFFFCDD2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Color(0xFFC62828),
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
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.check_circle,
                    size: 56,
                    color: const Color(0xFF43A047).withValues(alpha: 0.18),
                  ),
                ),
              ),
            ),
          if (player != null && !isBot && player.isHost)
            const Positioned(left: -3, top: -7, child: HostCrown(size: 22)),
          // What this player just said, for a couple of seconds. Laid over the
          // seat so a line of chat is visible without opening the panel.
          if (player != null) ?_seatChatBubble(player.name),
        ],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.lobbyKick),
        content: Text(l10n.lobbyKickConfirm(playerName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.kickPlayer(playerId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC62828),
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.lobbyKick),
          ),
        ],
      ),
    );
  }
}

/// Full-screen "uploading" barrier, shown as an OverlayEntry above whatever
/// route is current (including the profile dialog).
