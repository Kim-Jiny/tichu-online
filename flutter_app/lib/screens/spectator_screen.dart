import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';
import '../services/game_service.dart';
import '../services/session_service.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/mid_game_join.dart';
import '../widgets/spectator_controls.dart';

class SpectatorScreen extends StatefulWidget {
  const SpectatorScreen({super.key});

  @override
  State<SpectatorScreen> createState() => _SpectatorScreenState();
}

/// The size a spectator seat wants, worked out ahead of laying it out.
///
/// The four seats are the same widget, but the left and right ones are built
/// into a narrow column and the top and bottom ones into a wide, short band.
/// Each was then fitted to its own slot independently, and the two fits landed
/// nowhere near each other: a side seat is laid out AT the column width, so its
/// width ratio is always exactly 1 and it can never be scaled up, while a
/// top seat's hand is far narrower than its band and grows to fill it. On a
/// phone that put the side hands at about three quarters the size of the top
/// and bottom ones, and on a desktop browser at two thirds.
///
/// So the board works out one scale that every seat can afford, and hands each
/// slot the room that scale needs. The numbers below mirror the seat widget —
/// they have to, or the budget is for a seat nobody builds. The FittedBox in
/// [_SpectatorScreenState._buildScaledPlayerSection] stays as the safety net:
/// if this is optimistic, the seat shrinks rather than overflowing.
class _SeatMetrics {
  _SeatMetrics({
    required this.compact,
    required this.s,
    required this.cardBudget,
  });

  final bool compact;

  /// The screen-size factor the card art is drawn at.
  final double s;

  /// Cards to leave room for, or 0 when no hand is on show and the seat holds
  /// the card-request button instead.
  final int cardBudget;

  double get _avatar => compact ? 44 : 56;
  double get _cardWidth => (compact ? 24.0 : 30.0) * s;
  double get _cardHeight => (compact ? 36.0 : 45.0) * s;
  double get _overlapAcross => (compact ? 16.0 : 20.0) * s;
  double get _overlapDown => (compact ? 14.0 : 20.0) * s;

  /// Avatar, name line, the gap under it, the container padding and the margin.
  double get _chromeHeight =>
      _avatar +
      (compact ? 2 : 3) + // gap under the avatar
      (compact ? 15 : 16) + // the name line
      4 + // gap above the hand
      2 * (compact ? 6 : 8) + // container padding
      2 * (compact ? 2 : 4); // outer margin
  /// Container padding and outer margin, both sides.
  double get _chromeWidth => 2 * (compact ? 6 : 8) + 2 * (compact ? 2 : 4);

  /// Height of the button that stands in for a hand nobody may see: padding,
  /// the eye icon, a gap, one line of text and the border.
  double get _requestAreaHeight =>
      2 * (compact ? 6 : 8) +
      (compact ? 16 : 20) +
      (compact ? 1 : 2) +
      (compact ? 13 : 14) +
      2;

  /// Whether the seat holds anything that can give way under a height budget.
  ///
  /// The hand is Flexible with a scaleDown of its own; the request button is
  /// not, so budgeting a height for it can only overflow — which is exactly
  /// what a 40pt guess at a 54pt button did.
  bool get hasSqueezableHand => cardBudget > 0;

  double get _handAcross =>
      cardBudget == 0 ? 90 : _cardWidth + (cardBudget - 1) * _overlapAcross;
  double get _handDown => cardBudget == 0
      ? _requestAreaHeight
      : _cardHeight + (cardBudget - 1) * _overlapDown;

  /// A top or bottom seat: the hand lies across, so it is wide and short.
  Size get topNatural => Size(
    _handAcross + _chromeWidth,
    _chromeHeight + (cardBudget == 0 ? _requestAreaHeight : _cardHeight),
  );

  /// A side seat may be at most this many times taller than it is wide.
  ///
  /// A full hand on end is 300pt of cards over a 56pt avatar, which on a small
  /// phone made the seat an 80×378 ribbon — the photo is square and undistorted
  /// but the column it sits in reads as stretched. The cap makes the hand give
  /// way instead: it is the part that can afford to be denser, and it is the
  /// reason the whole seat could not be any wider.
  static const double _maxSideAspect = 4.2;

  /// A side seat: the hand stands on end, so it is narrow and tall. The width
  /// is the avatar's, which is wider than a rotated card.
  Size get sideNatural {
    final width = math.max(_avatar, _cardHeight + 4) + _chromeWidth;
    return Size(
      width,
      math.min(_chromeHeight + _handDown, width * _maxSideAspect),
    );
  }

  /// Everything stacks: two bands plus the side column, all in one height.
  double portraitScale(Size board) {
    final byHeight =
        board.height / (2 * topNatural.height + sideNatural.height);
    final byWidth = math.min(
      board.width / topNatural.width,
      // The side columns may take under a third of the width between them,
      // or the trick in the middle has nothing left.
      board.width * 0.30 / sideNatural.width,
    );
    return math.min(byHeight, byWidth).clamp(0.55, 2.0);
  }

  /// The sides run the full height; the bands share it with the trick, which
  /// keeps the middle third.
  double landscapeScale(Size board) {
    final byHeight = math.min(
      board.height * 0.33 / topNatural.height,
      board.height / sideNatural.height,
    );
    final byWidth = math.min(
      (board.width - 2 * sideNatural.width) / topNatural.width,
      board.width * 0.22 / sideNatural.width,
    );
    return math.min(byHeight, byWidth).clamp(0.55, 2.0);
  }
}

/// Cards to budget a seat for.
///
/// A hand shrinks as it is played, and sizing the board off the current count
/// would have every seat breathe between tricks. A full hand for as long as
/// anyone's cards are on show holds the layout still.
int _seatCardBudget(List players) {
  final anyVisible = players.any(
    (p) =>
        p is Map &&
        p['canSeeCards'] == true &&
        (p['cards'] as List?)?.isNotEmpty == true,
  );
  return anyVisible ? 14 : 0;
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
                  // No board yet: the router sends a spectator with no game to
                  // the shared waiting room, so this is only the instant
                  // between the two. A spinner, not a second waiting room.
                  if (!game.hasSpectatorGameState || state == null) {
                    return const Center(child: CircularProgressIndicator());
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

  /// Board bubbles go on the overlay, not inside the seat's own Stack —
  /// otherwise the next seat or the card layer paints over them.
  Widget _wrapWithBubble(String nickname, Widget seat) {
    return SeatBubbleAnchor(
      text: _seatChat.textFor(nickname),
      suppressed: _chatOpen,
      child: seat,
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
        // One scale for all four seats, and each slot sized to what that scale
        // needs — see _SeatMetrics for why fitting each seat to its own slot
        // left the side hands markedly smaller than the top and bottom ones.
        //
        // Every seat still goes through the scaling wrapper. Nothing here is
        // measured, only predicted, and a prediction that runs long has to
        // shrink rather than overflow ("BOTTOM OVERFLOWED BY 69 PIXELS" was
        // this screen, on a fold).
        final metrics = _SeatMetrics(
          compact: false,
          s: _s,
          cardBudget: _seatCardBudget(players),
        );
        final seatScale = metrics.portraitScale(constraints.biggest);
        final endSeatHeight = metrics.topNatural.height * seatScale;
        final sideWidth = metrics.sideNatural.width * seatScale;
        return Column(
          children: [
            if (players.length > 2)
              SizedBox(
                height: endSeatHeight,
                child: _buildScaledPlayerSection(
                  game,
                  players[2],
                  currentPlayer,
                ),
              ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (players.length > 3)
                    SizedBox(
                      width: sideWidth,
                      child: _buildScaledPlayerSection(
                        game,
                        players[3],
                        currentPlayer,
                        isLeft: true,
                        referenceWidth: metrics.sideNatural.width,
                        referenceHeight: metrics.hasSqueezableHand
                            ? metrics.sideNatural.height
                            : null,
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
                      child: _buildScaledPlayerSection(
                        game,
                        players[1],
                        currentPlayer,
                        isRight: true,
                        referenceWidth: metrics.sideNatural.width,
                        referenceHeight: metrics.hasSqueezableHand
                            ? metrics.sideNatural.height
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (players.isNotEmpty)
              SizedBox(
                height: endSeatHeight,
                child: _buildScaledPlayerSection(
                  game,
                  players[0],
                  currentPlayer,
                ),
              ),
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
        // One scale for all four seats — see _SeatMetrics. The tables of
        // breakpoints this replaces (72/86/104/150 for the columns, 92/108/
        // 150/240 for the bands) were each chosen for the screen that had just
        // gone wrong, and no two of them agreed on how big a seat should be.
        final metrics = _SeatMetrics(
          compact: compact,
          s: _s,
          cardBudget: _seatCardBudget(players),
        );
        final seatScale = metrics.landscapeScale(constraints.biggest);
        final sideWidth = metrics.sideNatural.width * seatScale;
        final playerSlotHeight = metrics.topNatural.height * seatScale;
        // Whatever the two bands leave, less the 4pt gaps around it.
        final trickSlotHeight = math.max(
          cramped ? 76.0 : 88.0,
          constraints.maxHeight - 2 * playerSlotHeight - 8,
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
                  referenceWidth: metrics.sideNatural.width,
                  referenceHeight: metrics.hasSqueezableHand
                      ? metrics.sideNatural.height
                      : null,
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
                  referenceWidth: metrics.sideNatural.width,
                  referenceHeight: metrics.hasSqueezableHand
                      ? metrics.sideNatural.height
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }

  /// [referenceWidth] — build the seat this wide instead of filling the slot.
  ///
  /// Only the side seats pass it, and it is the whole reason they can grow. A
  /// seat laid out at its slot's width has a width ratio of exactly 1, so
  /// BoxFit.contain never enlarges it however much room the column has; built
  /// at its natural width instead, it scales up to the column the way the top
  /// and bottom seats scale up to their band.
  ///
  /// [referenceHeight] — the seat's own budget, not the slot's. The hand inside
  /// is Flexible with a scaleDown of its own, so a hand longer than the budget
  /// packs tighter and the avatar and name keep their size. Passing the SLOT's
  /// height here is what broke this before: the seat overflowed inside the
  /// clamp and left the FittedBox nothing to measure.
  Widget _buildScaledPlayerSection(
    GameService game,
    Map<String, dynamic> player,
    String currentPlayerId, {
    bool isLeft = false,
    bool isRight = false,
    bool compact = false,
    double? referenceWidth,
    double? referenceHeight,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Width only. A maxHeight here defeated the FittedBox below: the seat
        // was forced into the band's height and overflowed *inside* that clamp
        // ("BOTTOM OVERFLOWED BY 69 PIXELS"), leaving FittedBox no natural
        // height to measure and nothing to scale. Unbounded vertically, the
        // seat lays out at its true size and the FittedBox shrinks it to fit.
        final child = ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: referenceWidth != null
                ? math.min(referenceWidth, constraints.maxWidth)
                : constraints.maxWidth,
            maxHeight: referenceHeight ?? double.infinity,
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
            // contain, not scaleDown: scaleDown only ever shrinks, so on a
            // tablet or an unfolded phone the seat stayed at its phone size in
            // the middle of a band twice as tall. Shrinking behaves the same as
            // before, which is what phones do.
            fit: BoxFit.contain,
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
                // The landscape bar is a single row, so this goes inline —
                // the portrait branch puts it on its own line instead. It was
                // only ever added there, which is why a fold (landscape by
                // default) had no way to break into a match at all.
                if (game.canJoinInProgress) ...[
                  const SizedBox(width: 6),
                  MidGameJoinButton(game: game),
                ],
                const SizedBox(width: 6),
                _buildSpectatorButton(game),
                const SizedBox(width: 6),
                _buildSoundButton(game),
                const SizedBox(width: 6),
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
                // Its own line under the status row, matching SpectatorHeader.
                // Sharing that row with the badge, the phase text and both
                // score chips overflowed a narrow phone once the button
                // carried a label.
                if (game.canJoinInProgress) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: MidGameJoinButton(game: game),
                  ),
                ],
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
      onTap: () => showSpectatorListDialog(context, game),
    );
  }

  Widget _buildChatButton(GameService game) {
    return SpectatorActionButton(
      icon: Icons.chat_bubble_outline_rounded,
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
      // Watching a match counts as being in one: open on the game on the table,
      // the same as the four game screens do. Without this the popup would fall
      // back to the combined record, which is the lobby's answer, not this
      // screen's.
      initialGame: game.currentGameType,
      isBot: isBot,
    );
  }
}
