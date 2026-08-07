import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../models/player.dart';
import '../services/game_service.dart';
import '../services/session_service.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/level_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/host_crown.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/title_chip.dart';
import '../widgets/spectator_controls.dart';

class SpectatorScreen extends StatefulWidget {
  const SpectatorScreen({super.key});

  @override
  State<SpectatorScreen> createState() => _SpectatorScreenState();
}

class _SpectatorScreenState extends State<SpectatorScreen> {
  bool _isLeaving = false;
  bool _chatOpen = false;
  bool _soundPanelOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  Widget _buildRecoveryLoading({required String title, String? subtitle}) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (subtitle != null && subtitle.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.82),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _lastChatMessageCount = 0;
  int _readChatCount = 0;

  /// The last thing each player said, shown briefly over their seat.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    // Treat chat history that already exists when joining as read, so the
    // unread badge only counts messages received after entering.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final count = context.read<GameService>().chatMessages.length;
      setState(() {
        _readChatCount = count;
        _lastChatMessageCount = count;
      });
    });
  }

  @override
  void dispose() {
    _seatChat.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _leaveRoom(GameService game) {
    if (_isLeaving) return;
    _isLeaving = true;
    game.leaveRoom();
  }

  /// Board scale, matching game_screen.dart's `_s`. Capped at 1.0 off the web
  /// so phones and tablets render exactly as before; a desktop window has the
  /// room to grow into and looked comically small at 1.0.
  double _s = 1.0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionService>();
    final media = MediaQuery.of(context);
    // Web takes the portrait layout, like every other screen: the app is
    // orientation-locked, so the landscape variants only ever run in a
    // browser and are the paths nobody exercises.
    final isLandscape = !kIsWeb && media.orientation == Orientation.landscape;
    // Same 1.3 ceiling as the boards it mirrors. Spectating a Tichu game
    // drawn at 1.6 next to playing one at 1.3 would just look like two
    // different apps.
    _s = (media.size.shortestSide / 400).clamp(0.72, kIsWeb ? 1.3 : 1.0);
    // C9: Wrap in ConnectionOverlay for reconnection support
    return ConnectionOverlay(
      child: PopScope(
        canPop: false,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF8F4F6),
                  Color(0xFFF0E8F0),
                  Color(0xFFE8F0F8),
                ],
              ),
            ),
            child: SafeArea(
              bottom: !isLandscape,
              child: Consumer<GameService>(
                builder: (context, game, _) {
                  if (session.isRestoring) {
                    return _buildRecoveryLoading(
                      title: L10n.of(context).spectatorRecovering,
                      subtitle: localizeRestorePhase(session, L10n.of(context)),
                    );
                  }

                  final destination = game.currentDestination;
                  if (destination != AppDestination.spectator) {
                    if (!_isLeaving) {
                      _isLeaving = true;
                    }
                    return _buildRecoveryLoading(
                      title: L10n.of(context).spectatorTransitioning,
                      subtitle: L10n.of(context).spectatorRecheckingState,
                    );
                  }
                  if (_isLeaving) {
                    _isLeaving = false;
                  }

                  final state = game.spectatorGameState;
                  if (!game.hasSpectatorGameState || state == null) {
                    return _buildWaitingRoomView(context, game, isLandscape);
                  }

                  return _buildSpectatorView(context, game, state, isLandscape);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaitingRoomView(
    BuildContext context,
    GameService game,
    bool isLandscape,
  ) {
    final players = game.roomPlayers;
    _seatChat.consume(game);

    return Stack(
      children: [
        Column(
          children: [
            // Top bar
            Container(
              // Flat, like the in-game spectator header — the waiting room used
              // a floating card while the game view next to it did not.
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              decoration: const BoxDecoration(
                color: Color(0xFFFDFBFA),
                border: Border(bottom: BorderSide(color: Color(0xFFEDE4E0))),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _leaveRoom(game),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF6A5A52),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8E0F8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.visibility,
                          size: 14,
                          color: Color(0xFF4A4080),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          L10n.of(context).spectatorWatching,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4A4080),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      game.currentRoomName,
                      style: const TextStyle(
                        color: Color(0xFF5A4038),
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildSpectatorButton(game),
                  const SizedBox(width: 6),
                  _buildSoundButton(game),
                  const SizedBox(width: 6),
                  _buildChatButton(game),
                ],
              ),
            ),

            // Player slots
            Expanded(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(isLandscape ? 12 : 20),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: isLandscape ? 920 : 560,
                    ),
                    padding: EdgeInsets.all(isLandscape ? 20 : 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Teams are a Tichu-with-fixed-seating thing. Everything
                        // else — Skull King, Mighty, Love Letter, random-seating
                        // Tichu — gets the flat grid. This used to be a
                        // `tichu && randomSeating` check with the team layout as
                        // the fallback, so a Mighty room was labelled TEAM A /
                        // TEAM B and drew players[0..3] only: seats five and six
                        // were simply missing from the waiting screen.
                        if (game.currentGameType != 'tichu' ||
                            game.roomRandomSeating)
                          ConstrainedBox(
                            // Two per row. The slots are a fixed 130 wide, so
                            // without this the Wrap fits four across on a
                            // tablet and two on a phone — the same room in two
                            // shapes. Two columns is also what the waiting room
                            // itself now uses.
                            constraints: const BoxConstraints(
                              maxWidth: 130 * 2 + 12,
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                for (int i = 0; i < players.length; i++)
                                  _buildPlayerSlot(game, players[i], i),
                              ],
                            ),
                          )
                        else if (isLandscape)
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 20,
                            runSpacing: 20,
                            children: [
                              _buildWaitingTeamCard(
                                label: 'TEAM A',
                                color: const Color(0xFF6A9BD1),
                                children: [
                                  _buildPlayerSlot(game, players[0], 0),
                                  _buildPlayerSlot(game, players[2], 2),
                                ],
                              ),
                              _buildWaitingTeamCard(
                                label: 'TEAM B',
                                color: const Color(0xFFF5B8C0),
                                children: [
                                  _buildPlayerSlot(game, players[1], 1),
                                  _buildPlayerSlot(game, players[3], 3),
                                ],
                              ),
                            ],
                          )
                        else ...[
                          _buildWaitingTeamLabel(
                            label: 'TEAM A',
                            color: const Color(0xFF6A9BD1),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildPlayerSlot(game, players[0], 0),
                              const SizedBox(width: 16),
                              _buildPlayerSlot(game, players[2], 2),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildWaitingTeamLabel(
                            label: 'TEAM B',
                            color: const Color(0xFFF5B8C0),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildPlayerSlot(game, players[1], 1),
                              const SizedBox(width: 16),
                              _buildPlayerSlot(game, players[3], 3),
                            ],
                          ),
                        ],
                        SizedBox(height: isLandscape ? 20 : 28),
                        // Waiting text
                        Text(
                          L10n.of(context).spectatorWaitingForGame,
                          style: const TextStyle(
                            color: Color(0xFF8A8A8A),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Sound panel overlay
        if (_soundPanelOpen) _buildSoundPanel(game),

        // Chat panel overlay
        if (_chatOpen) _buildChatPanel(game),
      ],
    );
  }

  Widget _buildWaitingTeamLabel({required String label, required Color color}) {
    return Text(
      label,
      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildWaitingTeamCard({
    required String label,
    required Color color,
    required List<Widget> children,
  }) {
    // Label + seats, no box. The seats have their own outlines, so a card
    // around them was a third nested border (page → panel → team → seat).
    return Container(
      width: 320,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          _buildWaitingTeamLabel(label: label, color: color),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: children,
          ),
        ],
      ),
    );
  }

  /// Waiting-room seat avatar: photo, bot art, or the nickname's initial.
  ///
  /// A level badge filled this slot before, and at 34dp a brown disc with a
  /// number in it reads as a score rather than as a person. Photo-less players
  /// get a plain default-avatar silhouette; the level still shows, as a small
  /// corner chip, the way the bot marker does.
  Widget _seatAvatar(GameService game, Player player) {
    const size = 42.0;
    final avatar = ProfileAvatar(
      photoUrl: game.resolvePhotoUrl(player.photoUrl),
      size: size,
      blocked: game.blockedUsers.contains(player.name),
      fallback: player.isBot
          ? BotAvatar(
              size: size,
              name: player.name,
              showBadge: true,
              speed: player.botSpeed,
            )
          : Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(
                color: Color(0xFFF0E7E3),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.person,
                size: 25,
                color: Color(0xFF9C8B84),
              ),
            ),
    );
    if (player.isBot || player.level == null) return avatar;
    return SizedBox(
      width: size,
      height: size,
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
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: LevelBadge(level: player.level, size: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// Board bubbles go on the overlay, not inside the seat's own Stack —
  /// otherwise the next seat or the card layer paints over them.
  Widget _wrapWithBubble(String nickname, Widget seat) {
    return SeatBubbleAnchor(
      text: _seatChat.textFor(nickname),
      suppressed: _chatOpen,
      child: seat,
    );
  }

  /// What [nickname] just said, or null once it has timed out.
  Widget? _seatChatBubble(String nickname) {
    final text = _seatChat.textFor(nickname);
    if (text == null) return null;
    return Positioned(
      left: 6,
      right: 6,
      bottom: 6,
      child: SeatChatBubble(
        text: text,
        fontSize: 11,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPlayerSlot(GameService game, Player? player, int slotIndex) {
    final bool isEmpty = player == null;
    final String name = isEmpty ? '' : player.name;
    final bool isReady = isEmpty ? false : player.isReady;
    // The banner someone paid for should show wherever their seat does. It
    // reached the waiting room's seats and stopped there, so buying one and
    // then being spectated meant it vanished. Bots have no inventory.
    final bannerGradient = (isEmpty || player.isBot)
        ? null
        : game.bannerGradient(player.bannerKey);
    final bannerText = (isEmpty || player.isBot)
        ? null
        : game.bannerTextColor(player.bannerKey);

    final content = Container(
      width: 130,
      // Fixed height equalizes empty / filled-no-title / filled-with-title
      // states. Without this the title row added ~18px so empty slots
      // looked shorter than seated ones.
      //
      // Sized for the tallest case and then some: 42dp avatar + 6 + title chip
      // + 2 + name, inside 14dp of padding top and bottom and a border that is
      // 2dp while ready and 1dp otherwise. This has now been raised twice by
      // "a couple of pixels" — 100, then 108, which still overflowed by 3 for a
      // player with a title — so the slack here is deliberate. Anything that
      // adds a line to the column needs to raise it again rather than trust
      // the fit.
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: bannerGradient != null
            ? null
            : (isEmpty ? const Color(0xFFF7F2F0) : Colors.white),
        gradient: bannerGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isEmpty
              ? const Color(0xFFD8CFCB)
              : isReady
              ? const Color(0xFF9ED6A5)
              : const Color(0xFFE0D8D4),
          width: isReady ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // The seated case drew a generic silhouette here and then repeated
          // the player's real avatar at 18dp beside the name — a photo owner saw
          // an anonymous icon above their own face. One avatar, in the slot the
          // silhouette had.
          if (isEmpty)
            const Icon(Icons.person_add, color: Color(0xFF9AA7B0), size: 28)
          else
            _seatAvatar(game, player),
          const SizedBox(height: 6),
          if (!isEmpty && player.titleName != null) ...[
            TitleChip(
              titleKey: player.titleKey,
              titleName: player.titleName,
              fontSize: 10,
              iconSize: 10,
            ),
            const SizedBox(height: 2),
          ],
          if (isEmpty)
            Text(
              L10n.of(context).spectatorSit,
              style: const TextStyle(
                color: Color(0xFF9AA7B0),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: bannerText ?? const Color(0xFF5A4038),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          // Host status is conveyed by the 👑 overhang on the top-left and
          // ready status by the subtle check watermark behind the slot — no
          // textual status line is rendered so the layout doesn't shift.
        ],
      ),
    );

    final stacked = Stack(
      clipBehavior: Clip.none,
      children: [
        content,
        if (!isEmpty && isReady)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Icon(
                  Icons.check_circle,
                  size: 56,
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.18),
                ),
              ),
            ),
          ),
        if (!isEmpty && player.isHost)
          const Positioned(left: -3, top: -7, child: HostCrown(size: 22)),
        // What this player just said, for a couple of seconds — the same
        // treatment the room waiting screen gives it, so a spectator sees the
        // conversation without opening the panel.
        if (!isEmpty) ?_seatChatBubble(name),
      ],
    );

    if (isEmpty) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => game.switchToPlayer(slotIndex),
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.blue.withValues(alpha: 0.2),
          child: stacked,
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showPlayerProfileDialog(name, game, isBot: player.isBot),
      child: stacked,
    );
  }

  Widget _buildSpectatorView(
    BuildContext context,
    GameService game,
    Map<String, dynamic> state,
    bool isLandscape,
  ) {
    _seatChat.consume(game);
    final players = (state['players'] as List?) ?? [];
    final currentTrick = (state['currentTrick'] as List?) ?? [];
    final phase = state['phase'] ?? '';
    final totalScores = state['totalScores'] as Map<String, dynamic>? ?? {};
    final currentPlayer = state['currentPlayer'] ?? '';
    final round = state['round'] ?? 1;
    final callRank = state['callRank'] as String?;
    final scoreHistory = (state['scoreHistory'] as List?) ?? [];
    final targetScore = state['targetScore'] as int?;

    return Stack(
      children: [
        Column(
          children: [
            _buildTopBar(
              context,
              game,
              phase,
              round,
              totalScores,
              scoreHistory,
              isLandscape,
              targetScore: targetScore,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: isLandscape
                    ? _buildLandscapeSpectatorBoard(
                        game,
                        players,
                        currentPlayer,
                        currentTrick,
                        callRank: callRank,
                      )
                    : _buildPortraitSpectatorBoard(
                        game,
                        players,
                        currentPlayer,
                        currentTrick,
                        callRank: callRank,
                      ),
              ),
            ),
          ],
        ),

        // Server error banner (e.g. "X has set always-deny" when a
        // card-view request fizzles). Plays the role of the in-game
        // _buildErrorBanner so spectators don't get silent no-ops.
        if (game.errorMessage != null)
          _buildSpectatorErrorBanner(game.errorMessage!),

        // Sound panel overlay
        if (_soundPanelOpen) _buildSoundPanel(game),

        // Chat panel overlay
        if (_chatOpen) _buildChatPanel(game),

        // Bug #10: Game end overlay for spectators
        if (phase == 'game_end') _buildGameEndOverlay(game, totalScores),
      ],
    );
  }

  Widget _buildSpectatorErrorBanner(String message) {
    return Positioned(
      bottom: 80,
      left: 20,
      right: 20,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEBEE),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE57373)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.info_outline,
                size: 16,
                color: Color(0xFFC62828),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  localizeServiceMessage(message, L10n.of(context)),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitSpectatorBoard(
    GameService game,
    List players,
    String currentPlayer,
    List currentTrick, {
    String? callRank,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Lock the left/right slot widths so a long nickname can't widen
        // the side column and pull the trick area off-center. Mirrors the
        // sideWidth pattern used in the landscape board.
        // The 22% is the intent; the ceiling was a phone's. On a wide window
        // it pinned the side seats at 108 while the middle took everything
        // else, so the two flanking players stayed small no matter the room.
        final sideWidth = (constraints.maxWidth * 0.22).clamp(
          76.0,
          kIsWeb ? 180.0 : 108.0,
        );
        return Column(
          children: [
            if (players.length > 2)
              _buildPlayerSection(game, players[2], currentPlayer),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (players.length > 3)
                    SizedBox(
                      width: sideWidth,
                      child: _buildPlayerSection(
                        game,
                        players[3],
                        currentPlayer,
                        isLeft: true,
                      ),
                    ),
                  Expanded(
                    child: _buildTrickArea(
                      currentTrick,
                      callRank: callRank,
                      players: players,
                    ),
                  ),
                  if (players.length > 1)
                    SizedBox(
                      width: sideWidth,
                      child: _buildPlayerSection(
                        game,
                        players[1],
                        currentPlayer,
                        isRight: true,
                      ),
                    ),
                ],
              ),
            ),
            if (players.isNotEmpty)
              _buildPlayerSection(game, players[0], currentPlayer),
          ],
        );
      },
    );
  }

  Widget _buildLandscapeSpectatorBoard(
    GameService game,
    List players,
    String currentPlayer,
    List currentTrick, {
    String? callRank,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cramped = constraints.maxHeight < 390;
        final compact = constraints.maxHeight < 520;
        final sideWidth = cramped
            ? 72.0
            : (constraints.maxHeight > 620 ? 104.0 : 86.0);
        // A full-size seat (56px avatar + name + badges + the card-view button)
        // wants roughly 170px. The old ceiling stopped at 108 even when the
        // window was 800px tall, so on a desktop browser the seat overflowed its
        // own background: the card-view button ended up drawn outside the
        // profile box, and the bottom seat ran off the viewport. Phone
        // landscape is unaffected — it stays under the 700px threshold and keeps
        // the tighter caps.
        final slotCeiling = constraints.maxHeight > 700
            ? 240.0
            : (constraints.maxHeight > 620 ? 108.0 : 92.0);
        final playerSlotHeight =
            (constraints.maxHeight * (cramped ? 0.20 : (compact ? 0.23 : 0.26)))
                .clamp(cramped ? 48.0 : 56.0, slotCeiling);
        final trickSlotHeight =
            (constraints.maxHeight * (cramped ? 0.34 : (compact ? 0.40 : 0.46)))
                .clamp(
                  cramped ? 76.0 : 88.0,
                  constraints.maxHeight > 700
                      ? 380.0
                      : (constraints.maxHeight > 620 ? 180.0 : 132.0),
                );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (players.length > 3)
              SizedBox(
                width: sideWidth,
                child: _buildScaledPlayerSection(
                  game,
                  players[3],
                  currentPlayer,
                  isLeft: true,
                  compact: compact,
                ),
              ),
            if (players.length > 3) const SizedBox(width: 6),
            Expanded(
              child: Column(
                children: [
                  if (players.length > 2)
                    SizedBox(
                      height: playerSlotHeight,
                      child: _buildScaledPlayerSection(
                        game,
                        players[2],
                        currentPlayer,
                        compact: compact,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: trickSlotHeight,
                          maxWidth: constraints.maxWidth,
                        ),
                        child: _buildTrickArea(
                          currentTrick,
                          compact: compact,
                          landscapeCompact: compact,
                          callRank: callRank,
                          players: players,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (players.isNotEmpty)
                    SizedBox(
                      height: playerSlotHeight,
                      child: _buildScaledPlayerSection(
                        game,
                        players[0],
                        currentPlayer,
                        compact: compact,
                      ),
                    ),
                ],
              ),
            ),
            if (players.length > 1) const SizedBox(width: 6),
            if (players.length > 1)
              SizedBox(
                width: sideWidth,
                child: _buildScaledPlayerSection(
                  game,
                  players[1],
                  currentPlayer,
                  isRight: true,
                  compact: compact,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildScaledPlayerSection(
    GameService game,
    Map<String, dynamic> player,
    String currentPlayerId, {
    bool isLeft = false,
    bool isRight = false,
    bool compact = false,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final child = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
          ),
          child: _buildPlayerSection(
            game,
            player,
            currentPlayerId,
            isLeft: isLeft,
            isRight: isRight,
            compact: compact,
          ),
        );
        // Always scale down, not just on short phone-landscape viewports.
        // The seat slots are height-capped (108px at most), but `compact` and
        // `cramped` both switch off on a tall window — so a desktop browser
        // built the full-size seat and dropped it into that cap unscaled. The
        // top seat's card-view button spilled outside its profile box and the
        // bottom seat ran off the viewport. BoxFit.scaleDown does nothing when
        // the child already fits, so phones are unaffected.
        return Align(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildGameEndOverlay(GameService game, Map<String, dynamic> scores) {
    final teamA = scores['teamA'] ?? 0;
    final teamB = scores['teamB'] ?? 0;
    final l10n = L10n.of(context);
    final winnerText = teamA > teamB
        ? l10n.spectatorTeamWin('A')
        : teamB > teamA
        ? l10n.spectatorTeamWin('B')
        : l10n.spectatorDraw;

    return Container(
      color: Colors.black54,
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                winnerText,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.spectatorTeamScores(teamA as int, teamB as int),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6A5A52),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.spectatorAutoReturn,
                style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(
    BuildContext context,
    GameService game,
    String phase,
    int round,
    Map<String, dynamic> scores,
    List scoreHistory,
    bool isLandscape, {
    int? targetScore,
  }) {
    // Flat bar, not a floating card. A card here fought with the board's own
    // cards below it — two levels of elevation stacked in the top 90dp — and the
    // 12dp margin on every side ate width the room name needed.
    return Container(
      padding: EdgeInsets.fromLTRB(
        isLandscape ? 10 : 8,
        isLandscape ? 6 : 8,
        isLandscape ? 10 : 12,
        isLandscape ? 6 : 8,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFDFBFA),
        border: Border(bottom: BorderSide(color: Color(0xFFEDE4E0))),
      ),
      child: isLandscape
          ? Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  onPressed: () => _leaveRoom(game),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Color(0xFF6A5A52),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E0F8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.visibility,
                        size: 12,
                        color: Color(0xFF4A4080),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        L10n.of(context).spectatorWatching,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4A4080),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'R$round | ${_getPhaseText(phase)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF8A7E78),
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _buildScoreHistoryTap(
                  scoreHistory,
                  scores,
                  targetScore: targetScore,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildScoreChip(
                        'A',
                        scores['teamA'] ?? 0,
                        const Color(0xFF6A9BD1),
                        compact: true,
                      ),
                      const SizedBox(width: 4),
                      _buildScoreChip(
                        'B',
                        scores['teamB'] ?? 0,
                        const Color(0xFFF5B8C0),
                        compact: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _buildSpectatorButton(game),
                const SizedBox(width: 4),
                _buildSoundButton(game),
                const SizedBox(width: 4),
                _buildChatButton(game),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _leaveRoom(game),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Color(0xFF6A5A52),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // The room name was nowhere in this bar, while four icon
                    // buttons sat where it could go. Chat keeps its own button
                    // because its unread badge is the one that matters live;
                    // the other three are look-ups and settings.
                    Expanded(
                      child: Text(
                        game.currentRoomName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF4E3A34),
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    _buildSpectatorButton(game),
                    const SizedBox(width: 6),
                    _buildSoundButton(game),
                    const SizedBox(width: 6),
                    _buildChatButton(game),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // On the status line, matching SpectatorHeader — on the
                    // title row it was squeezing the room name.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8E0F8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.visibility,
                            size: 12,
                            color: Color(0xFF4A4080),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            L10n.of(context).spectatorWatching,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4A4080),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'R$round | ${_getPhaseText(phase)}',
                      style: const TextStyle(
                        color: Color(0xFF8A7E78),
                        fontSize: 12,
                      ),
                    ),
                    // What score the game is played to. Players see it in their
                    // own top bar; spectators had no way to know.
                    if (targetScore != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        L10n.of(context).spectatorTargetScore(targetScore),
                        style: const TextStyle(
                          color: Color(0xFFA89C96),
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const Spacer(),
                    // The score itself opens the history — it is what you are
                    // already looking at when you wonder how it got there, and
                    // it saves a slot in the bar.
                    _buildScoreHistoryTap(
                      scoreHistory,
                      scores,
                      targetScore: targetScore,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildScoreChip(
                            'A',
                            scores['teamA'] ?? 0,
                            const Color(0xFF6A9BD1),
                          ),
                          const SizedBox(width: 6),
                          _buildScoreChip(
                            'B',
                            scores['teamB'] ?? 0,
                            const Color(0xFFF5B8C0),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  /// Wraps the score chips so tapping them opens the round-by-round history.
  Widget _buildScoreHistoryTap(
    List scoreHistory,
    Map<String, dynamic> scores, {
    required Widget child,
    int? targetScore,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTichuScoreHistoryDialog(
        context,
        history: scoreHistory
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        totalA: scores['teamA'] ?? 0,
        totalB: scores['teamB'] ?? 0,
        targetScore: targetScore,
      ),
      child: child,
    );
  }

  Widget _buildScoreChip(
    String label,
    dynamic score,
    Color color, {
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(compact ? 7 : 8),
      ),
      child: Text(
        '$label: $score',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: compact ? 11 : 12,
        ),
      ),
    );
  }

  String _getPhaseText(String phase) {
    final l10n = L10n.of(context);
    switch (phase) {
      case 'large_tichu_phase':
        return l10n.spectatorPhaseLargeTichu;
      case 'card_exchange':
        return l10n.spectatorPhaseCardExchange;
      case 'playing':
        return l10n.spectatorPhasePlaying;
      case 'round_end':
        return l10n.spectatorPhaseRoundEnd;
      case 'game_end':
        return l10n.spectatorPhaseGameEnd;
      default:
        return phase;
    }
  }

  Widget _buildPlayerSection(
    GameService game,
    Map<String, dynamic> player,
    String currentPlayerId, {
    bool isLeft = false,
    bool isRight = false,
    bool compact = false,
  }) {
    final playerId = player['id'] ?? '';
    final name = player['name'] ?? '';
    final cards = (player['cards'] as List?) ?? [];
    final cardCount = player['cardCount'] ?? 0;
    final canSeeCards = player['canSeeCards'] == true;
    final isCurrentTurn = playerId == currentPlayerId;
    final hasFinished = player['hasFinished'] ?? false;
    final finishPosition = player['finishPosition'] ?? 0;
    final hasSmallTichu = player['hasSmallTichu'] ?? false;
    final hasLargeTichu = player['hasLargeTichu'] ?? false;
    final connected = player['connected'] ?? true;
    final vertical = isLeft || isRight;

    final isPending = game.pendingCardViewRequests.contains(playerId);

    // Faint team tint as the slot background (replaces the removed dot
    // indicator) so spectators can still tell which team each player is on
    // at a glance. Team A → cool blue, Team B → warm rose.
    final team = player['team']?.toString() ?? '';
    final slotBg = team == 'A'
        ? const Color(0xFFE9F2FB)
        : team == 'B'
        ? const Color(0xFFFBECEF)
        : Colors.white.withValues(alpha: 0.98);

    final isBot = player['isBot'] == true;
    // Spectating a game had no way into a profile at all — so no way to block or
    // report someone whose nickname or photo is the problem. The tap belongs to
    // the card-view button inside, so the seat takes a long-press, and the name
    // row below takes a tap of its own since nothing else wants it.
    return GestureDetector(
      onTap: () => _showPlayerProfileDialog(name, game, isBot: isBot),
      onLongPress: () => _showPlayerProfileDialog(name, game, isBot: isBot),
      child: _wrapWithBubble(
        name,
        Container(
          margin: EdgeInsets.all(compact ? 2 : 4),
          padding: EdgeInsets.all(compact ? 6 : 8),
          decoration: BoxDecoration(
            color: slotBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isCurrentTurn
                  ? const Color(0xFFF3C97A)
                  : const Color(0xFFE6DDD8),
              width: isCurrentTurn ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFE5DAD6).withValues(alpha: 0.35),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Own row rather than inline before the name. The side slots are only
              // ~79dp wide, so an inline avatar had to stay at 16-20px to leave the
              // nickname any room — too small to make out a face.
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 2 : 3),
                child: ProfileAvatar(
                  photoUrl: game.resolvePhotoUrl(player['photoUrl'] as String?),
                  size: (compact ? 44 : 56).toDouble(),
                  blocked: game.blockedUsers.contains(name),
                  fallback: isBot
                      ? BotAvatar(
                          size: (compact ? 44 : 56).toDouble(),
                          name: name,
                          showBadge: true,
                        )
                      : DefaultAvatar(size: (compact ? 44 : 56).toDouble()),
                ),
              ),
              // Player name and status
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!connected)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(Icons.wifi_off, size: 12, color: Colors.red),
                    ),
                  // Team letter, the same badge the player screen puts before a
                  // nickname. The slot's background tint alone was too quiet to map
                  // a name to the "A:" / "B:" score chips at a glance.
                  if (team == 'A' || team == 'B')
                    Padding(
                      padding: EdgeInsets.only(right: compact ? 3 : 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: team == 'A'
                              ? const Color(0xFFE3F0FF)
                              : const Color(0xFFFFE8EC),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: team == 'A'
                                ? const Color(0xFF4A90D9)
                                : const Color(0xFFD24B4B),
                            width: 0.7,
                          ),
                        ),
                        child: Text(
                          team,
                          style: TextStyle(
                            fontSize: compact ? 8 : 9,
                            fontWeight: FontWeight.bold,
                            color: team == 'A'
                                ? const Color(0xFF4A90D9)
                                : const Color(0xFFD24B4B),
                          ),
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: connected
                            ? const Color(0xFF4E3A34)
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: compact ? 11 : 12,
                      ),
                    ),
                  ),
                ],
              ),
              // Badges on their own line. Sharing the name's row meant every badge
              // stole width from it — a finish rank (#1) was enough to ellipsize a
              // perfectly short nickname in the ~79dp side slots.
              if (hasLargeTichu ||
                  hasSmallTichu ||
                  (hasFinished && finishPosition > 0))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // "LT"/"T" at 8pt read as noise — a Tichu call is the most
                      // consequential thing a spectator can notice about a hand.
                      // Same wording and colours as the player screen's badge
                      // ("라지"/"스몰", red/blue), just sized for the slot.
                      if (hasLargeTichu)
                        _tichuCallBadge(
                          L10n.of(context).gameBadgeLarge,
                          const Color(0xFFFF4444),
                          const Color(0xFFCC0000),
                        )
                      else if (hasSmallTichu)
                        _tichuCallBadge(
                          L10n.of(context).gameBadgeSmall,
                          const Color(0xFF2979FF),
                          const Color(0xFF1565C0),
                        ),
                      if (hasFinished && finishPosition > 0) ...[
                        if (hasLargeTichu || hasSmallTichu)
                          const SizedBox(width: 4),
                        Text(
                          '#$finishPosition',
                          style: const TextStyle(
                            color: Color(0xFF6BBE7A),
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              // Cards or request button
              if (hasFinished && cardCount == 0)
                Padding(
                  padding: EdgeInsets.all(compact ? 6 : 8),
                  child: Text(
                    L10n.of(context).spectatorFinished,
                    style: TextStyle(
                      color: const Color(0xFF9A8E8A),
                      fontSize: compact ? 9 : 10,
                    ),
                  ),
                )
              else if (canSeeCards && cards.isNotEmpty)
                // Only the card strip gives way when the slot runs out of height.
                // Moving the avatar onto its own row cost ~28dp, and a 13-card
                // vertical strip in a side slot overflowed the bottom by that much.
                // Scaling the whole seat instead would shrink the avatar and name
                // back down, which is what this change was for.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: vertical
                        ? _buildRotatedCards(
                            cards,
                            isLeft: isLeft,
                            compact: compact,
                          )
                        : _buildHorizontalCards(cards, compact: compact),
                  ),
                )
              else
                _buildCardRequestArea(
                  game,
                  playerId,
                  cardCount,
                  isPending,
                  vertical,
                  compact: compact,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tichuCallBadge(String label, Color bg, Color border) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildRotatedCards(
    List cards, {
    bool isLeft = true,
    bool compact = false,
  }) {
    final cardWidth = (compact ? 24.0 : 30.0) * _s;
    final cardHeight = (compact ? 36.0 : 45.0) * _s;
    final overlap = (compact ? 14.0 : 20.0) * _s;

    final totalHeight = cardHeight + (cards.length - 1) * overlap;
    // 좌측: 90도 (pi/2), 우측: 270도 (3*pi/2 = -pi/2)
    final angle = isLeft ? 1.5708 : -1.5708;

    return SizedBox(
      width: cardHeight + 4, // 회전 후 잘림 방지
      // Cap at a full 14-card hand height + small buffer. Previous
      // 180/300 caps clipped the last card when holding a full hand.
      height: totalHeight.clamp(40.0, (compact ? 240.0 : 320.0) * _s),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < cards.length; i++)
            Positioned(
              top: i * overlap,
              left: 0,
              child: SizedBox(
                width: cardHeight,
                height: cardHeight,
                child: Center(
                  child: Transform.rotate(
                    angle: angle,
                    child: SizedBox(
                      width: cardWidth,
                      height: cardHeight,
                      child: PlayingCard(
                        cardId: cards[i].toString(),
                        width: cardWidth,
                        height: cardHeight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCardRequestArea(
    GameService game,
    String playerId,
    int cardCount,
    bool isPending,
    bool vertical, {
    bool compact = false,
  }) {
    if (isPending) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEFD8),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 14 : 16,
              height: compact ? 14 : 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFF2A65A),
              ),
            ),
            SizedBox(height: compact ? 3 : 4),
            Text(
              L10n.of(context).spectatorRequesting(cardCount),
              style: TextStyle(
                color: const Color(0xFFB58343),
                fontSize: compact ? 9 : 10,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => game.requestCardView(playerId),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF4FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFB7D3EF)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.visibility,
              color: const Color(0xFF4F88C8),
              size: compact ? 16 : 20,
            ),
            SizedBox(height: compact ? 1 : 2),
            // Side slots are ~79dp wide and the full label broke into three
            // lines there ("패 보 기 요 청 (4 장)"). The eye icon above already
            // says what the button does, so the count alone is enough.
            Text(
              vertical
                  ? L10n.of(context).spectatorCardCount(cardCount)
                  : L10n.of(context).spectatorRequestCardView(cardCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                color: const Color(0xFF4F88C8),
                fontSize: compact ? 9 : 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHorizontalCards(List cards, {bool compact = false}) {
    final cardWidth = (compact ? 24.0 : 30.0) * _s;
    final cardHeight = (compact ? 36.0 : 45.0) * _s;
    final overlap = (compact ? 16.0 : 20.0) * _s;

    final totalWidth = cardWidth + (cards.length - 1) * overlap;

    // Cap at a full 14-card hand width + small buffer. The previous
    // 200/280 caps clipped the rightmost card when a player held a full
    // hand (14 × 20 + 30 = 290 non-compact / 14 × 16 + 24 = 232 compact).
    return SizedBox(
      height: cardHeight,
      width: totalWidth.clamp(40.0, (compact ? 244.0 : 304.0) * _s),
      child: Stack(
        children: [
          for (int i = 0; i < cards.length; i++)
            Positioned(
              left: i * overlap,
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: PlayingCard(
                  cardId: cards[i].toString(),
                  width: cardWidth,
                  height: cardHeight,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSoundButton(GameService game) {
    return SpectatorActionButton(
      icon: game.sfxVolume <= 0.01 ? Icons.volume_off : Icons.volume_up,
      active: _soundPanelOpen,
      onTap: () => setState(() => _soundPanelOpen = !_soundPanelOpen),
    );
  }

  Widget _buildSoundPanel(GameService game) {
    return Positioned(
      top: 96,
      right: 12,
      child: SpectatorSoundPanel(game: game, width: 180),
    );
  }

  Widget _buildSpectatorButton(GameService game) {
    return SpectatorActionButton(
      icon: Icons.people_alt,
      active: false,
      badgeCount: game.spectators.length,
      onTap: () => showSpectatorListDialog(context, game.spectators),
    );
  }

  Widget _buildChatButton(GameService game) {
    return SpectatorActionButton(
      icon: Icons.chat_bubble_outline,
      active: _chatOpen,
      badgeCount: _chatOpen
          ? 0
          : (game.chatMessages.length - _readChatCount).clamp(0, 99),
      onTap: () => setState(() {
        _chatOpen = !_chatOpen;
        if (_chatOpen) {
          _readChatCount = game.chatMessages.length;
          _scrollChatToBottom();
        }
      }),
    );
  }

  /// The colour the game being spectated wears in the lobby and on its own
  /// board.
  Color _spectatorAccentColor(String? gameType) {
    switch (gameType) {
      case 'love_letter':
        return const Color(0xFFE91E63);
      case 'mighty':
        return const Color(0xFF1565C0);
      case 'skull_king':
        return const Color(0xFF21455F);
      default:
        return const Color(0xFF64B5F6);
    }
  }

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      // Panel only builds while open, so keep the read marker current to
      // avoid a stale unread badge after the user closes the chat.
      _readChatCount = game.chatMessages.length;
      _scrollChatToBottom();
    }
    // One spectator screen serves all four games, so its chat has to take the
    // colour of the game being watched instead of Tichu's blue.
    final accent = _spectatorAccentColor(game.currentGameType);
    return DraggableChatPanel(
      accentColor: accent,
      sendIconColor: accent,
      title: L10n.of(context).spectatorChat,
      hintText: L10n.of(context).spectatorMessageHint,
      controller: _chatController,
      scrollController: _chatScrollController,
      onSend: () => _sendChatMessage(game),
      onClose: () => setState(() => _chatOpen = false),
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
        final isBlocked = game.isBlocked(sender);
        if (isBlocked) return const SizedBox.shrink();
        return _buildChatBubble(sender, message, isMe);
      },
    );
  }

  Widget _buildChatBubble(String sender, String message, bool isMe) {
    return ChatBubble(
      sender: sender,
      message: message,
      isMe: isMe,
      game: context.read<GameService>(),
      mineColor: _spectatorAccentColor(
        context.read<GameService>().currentGameType,
      ),
      onTap: sender.isEmpty
          ? null
          : () => _showPlayerProfileDialog(sender, context.read<GameService>()),
    );
  }

  void _scrollChatToBottom() {
    // ListView is reverse:true so offset 0 == bottom.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollController.hasClients) return;
      _chatScrollController.jumpTo(0);
    });
  }

  void _sendChatMessage(GameService game) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    game.sendChatMessage(message);
    _chatController.clear();
    _scrollChatToBottom();
  }

  Widget _buildTrickArea(
    List currentTrick, {
    bool compact = false,
    bool landscapeCompact = false,
    String? callRank,
    List players = const [],
  }) {
    final hasCall = callRank != null && callRank.isNotEmpty;

    Widget callBadge() {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x33FF4444),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFF4444), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🐦', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 3),
            Text(
              L10n.of(context).gameCall(callRank!),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFFFF4444),
              ),
            ),
          ],
        ),
      );
    }

    if (currentTrick.isEmpty) {
      return Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                L10n.of(context).spectatorNewTrick,
                style: TextStyle(
                  color: const Color(0xFF9A8E8A),
                  fontSize: compact ? 12 : 14,
                ),
              ),
              if (hasCall) ...[SizedBox(height: compact ? 4 : 6), callBadge()],
            ],
          ),
        ),
      );
    }

    final lastPlay = currentTrick.last;
    final playerName = lastPlay['playerName'] ?? '';
    final cards = (lastPlay['cards'] as List?) ?? [];
    final lastCombo = (lastPlay['combo'] ?? '') as String;
    final lastComboValue = (lastPlay['comboValue'] as num?)?.toDouble() ?? 0;

    // Color by the playing player's team so the trick box matches the seat
    // tint (Team A → blue, Team B → rose). Falls back to blue when the team
    // can't be resolved. Previously this alternated by play index, which
    // clashed with the team-colored seats.
    final lastPlayerId = (lastPlay['playerId'] ?? '').toString();
    String lastTeam = '';
    for (final p in players) {
      if (p is Map && (p['id']?.toString() ?? '') == lastPlayerId) {
        lastTeam = p['team']?.toString() ?? '';
        break;
      }
    }
    final isBlue = lastTeam != 'B';
    final bgColor = isBlue ? const Color(0xFFE3F0FF) : const Color(0xFFFFE8EC);
    final borderColor = isBlue
        ? const Color(0xFFB3D4F7)
        : const Color(0xFFF5C0C8);
    final nameColor = isBlue
        ? const Color(0xFF4A90D9)
        : const Color(0xFFD94A5A);

    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasCall) ...[callBadge(), SizedBox(height: compact ? 4 : 6)],
            Text(
              L10n.of(context).spectatorPlayedCards(
                playerName.length > 8
                    ? '${playerName.substring(0, 8)}..'
                    : playerName,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12 : 14,
                fontWeight: FontWeight.bold,
                color: nameColor,
              ),
            ),
            SizedBox(height: compact ? 4 : 6),
            _buildOverlappedCards(
              cards,
              compact: compact,
              forceSingleRow: landscapeCompact,
              combo: lastCombo,
              comboValue: lastComboValue,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlappedCards(
    List cards, {
    bool compact = false,
    bool forceSingleRow = false,
    String combo = '',
    double comboValue = 0,
  }) {
    final double cardW = (compact ? 24 : 36) * _s;
    final double cardH = (compact ? 34 : 50) * _s;
    final double minOverlap = (compact ? 10 : 20) * _s;
    final double maxOverlap = (compact ? 18 : 30) * _s;

    final isPhoenixSingleTrick =
        combo == 'single' &&
        cards.length == 1 &&
        cards[0].toString() == 'special_phoenix' &&
        comboValue > 1;
    final String? phoenixBeatLabel = isPhoenixSingleTrick
        ? _phoenixBeatLabel(comboValue)
        : null;

    Widget playingCard(String cardId) {
      final card = PlayingCard(
        cardId: cardId,
        width: cardW,
        height: cardH,
        isInteractive: false,
      );
      if (cardId != 'special_phoenix' || phoenixBeatLabel == null) return card;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC107),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                phoenixBeatLabel,
                style: TextStyle(
                  fontSize: compact ? 8 : 9,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF5A4038),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (cards.length <= 4) {
      return Wrap(
        alignment: WrapAlignment.center,
        spacing: 3,
        children: cards.map((c) => playingCard(c.toString())).toList(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 16;
        final neededOverlap = cards.length > 1
            ? (availableWidth - cardW) / (cards.length - 1)
            : availableWidth;

        if (neededOverlap >= minOverlap || forceSingleRow) {
          final overlap =
              (forceSingleRow
                      ? neededOverlap
                      : neededOverlap.clamp(minOverlap, maxOverlap))
                  .clamp(compact ? 7.0 : minOverlap, maxOverlap);
          final totalWidth = cardW + overlap * (cards.length - 1);
          return Center(
            child: SizedBox(
              width: totalWidth.clamp(cardW, constraints.maxWidth),
              height: cardH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int i = 0; i < cards.length; i++)
                    Positioned(
                      left: i * overlap,
                      child: PlayingCard(
                        cardId: cards[i].toString(),
                        width: cardW,
                        height: cardH,
                        isInteractive: false,
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        final mid = (cards.length + 1) ~/ 2;
        final row1 = cards.sublist(0, mid);
        final row2 = cards.sublist(mid);

        Widget buildRow(List rowCards) {
          final overlap = rowCards.length > 1
              ? ((availableWidth - cardW) / (rowCards.length - 1)).clamp(
                  minOverlap,
                  maxOverlap,
                )
              : 0.0;
          final totalWidth = cardW + overlap * (rowCards.length - 1);
          return SizedBox(
            width: totalWidth,
            height: cardH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (int i = 0; i < rowCards.length; i++)
                  Positioned(
                    left: i * overlap,
                    child: PlayingCard(
                      cardId: rowCards[i].toString(),
                      width: cardW,
                      height: cardH,
                      isInteractive: false,
                    ),
                  ),
              ],
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [buildRow(row1), const SizedBox(height: 4), buildRow(row2)],
        );
      },
    );
  }

  String _phoenixBeatLabel(double comboValue) {
    final beat = comboValue.floor();
    if (beat >= 14) return '↑A';
    if (beat == 13) return '↑K';
    if (beat == 12) return '↑Q';
    if (beat == 11) return '↑J';
    return '↑$beat';
  }

  // ====================== PROFILE DIALOG ======================

  void _showPlayerProfileDialog(
    String nickname,
    GameService game, {
    bool isBot = false,
  }) {
    showPlayerProfileDialog(
      context,
      nickname,
      game,
      subtitle: L10n.of(context).gamePlayerProfile,
      isBot: isBot,
    );
  }
}
