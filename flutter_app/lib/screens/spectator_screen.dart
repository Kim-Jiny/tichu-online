import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:math' as math;

import 'dart:ui' show FontFeature, ImageFilter;
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

class _SpectatorScreenState extends State<SpectatorScreen> {
  bool _isLeaving = false;
  bool _chatOpen = false;
  bool _soundPanelOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  // Currently-viewed player id — 하단 손패 영역에 이 사람의 카드를 보여준다.
  // SK 관전 화면과 동일한 모델. 승인 전이면 요청 스피너, 승인 후엔 실제 손패.
  String? _viewingPlayerId;
  Timer? _cardViewRequestTimer;

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
    _cardViewRequestTimer?.cancel();
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

        // 하단 손패 영역 — SK 관전과 동일 상태 머신.
        // 대상 없음(안내) / 요청 중 / 승인(패) / 거절 4가지 상태를 모두 처리하므로
        // 항상 렌더링한다.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildSpectatorHandArea(game, players),
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
        if (phase == 'game_end')
          _buildGameEndOverlay(game, totalScores, players),
      ],
    );
  }

  // 관전자용 하단 손패 영역. SK 의 _buildSpectatorHandArea 와 동일한 상태 머신:
  // 대상 없음(안내) / 요청 중 / 승인됨 / 거절.
  Widget _buildSpectatorHandArea(GameService game, List players) {
    BoxDecoration panelBg() => BoxDecoration(
      color: Colors.white.withValues(alpha: 0.92),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
    );

    final viewingId = _viewingPlayerId;
    // 대상 없음 — 좌석 탭으로 요청하라고 안내하는 상시 바.
    if (viewingId == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: panelBg(),
        child: Text(
          L10n.of(context).skGameTapToRequestCards,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8A7A72),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final viewingPlayer = players.cast<Map<String, dynamic>?>().firstWhere(
      (p) => (p?['id']?.toString() ?? '') == viewingId,
      orElse: () => null,
    );
    if (viewingPlayer == null) return const SizedBox.shrink();
    final name = viewingPlayer['name'] ?? '';
    final canSeeCards = viewingPlayer['canSeeCards'] == true;
    final cards = (viewingPlayer['cards'] as List?) ?? const [];
    final isApproved =
        game.approvedCardViews.contains(viewingId) && canSeeCards;
    final isPending = game.pendingCardViewRequests.contains(viewingId);

    // 요청 중 — 스피너 + 라벨.
    if (isPending && !isApproved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: panelBg(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFFB74D),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              L10n.of(context).skGameRequestingCardView(name),
              style: const TextStyle(
                color: Color(0xFF8A7A72),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // 승인 — 손패 노출.
    if (isApproved) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        decoration: panelBg(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    child: Text(
                      L10n.of(context).skGamePlayerHand(name),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF5A4038),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color(0xFF8A7A72),
                      ),
                      onPressed: () => setState(() => _viewingPlayerId = null),
                    ),
                  ),
                ],
              ),
            ),
            if (cards.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  L10n.of(context).skGameNoCards,
                  style: const TextStyle(
                    color: Color(0xFF8A7A72),
                    fontSize: 12,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildHorizontalCards(cards),
              ),
          ],
        ),
      );
    }

    // 거절/만료 — 안내 후 사용자가 다른 좌석을 탭하도록.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: panelBg(),
      child: Row(
        children: [
          Expanded(
            child: Text(
              L10n.of(context).skGameCardViewRejected(name),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8A7A72),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              padding: EdgeInsets.zero,
              splashRadius: 18,
              icon: const Icon(Icons.close, size: 18, color: Color(0xFF8A7A72)),
              onPressed: () => setState(() => _viewingPlayerId = null),
            ),
          ),
        ],
      ),
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
    return _buildRingSpectatorBoard(
      game,
      players,
      currentPlayer,
      currentTrick,
      callRank: callRank,
      isLandscape: false,
    );
  }

  Widget _buildLandscapeSpectatorBoard(
    GameService game,
    List players,
    String currentPlayer,
    List currentTrick, {
    String? callRank,
  }) {
    return _buildRingSpectatorBoard(
      game,
      players,
      currentPlayer,
      currentTrick,
      callRank: callRank,
      isLandscape: true,
    );
  }

  // 링 레이아웃. 티츄 4인 관전은 위/아래 대칭 4-corner (N/E/S/W)로,
  // 상단 두 좌석과 하단 두 좌석의 세로 간격이 동일하다. 3인/2인 관전은
  // SK 규칙을 그대로 이어받는다. 좌석 배경 상자 없이 사진이 좌석의 가장자리.
  Widget _buildRingSpectatorBoard(
    GameService game,
    List players,
    String currentPlayer,
    List currentTrick, {
    String? callRank,
    required bool isLandscape,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final boardScale = math
            .min(width / 360.0, height / 400.0)
            .clamp(0.78, 1.45);
        // 실제 손패는 하단 손패 영역으로 이관됐으므로 좌석은 게임 화면 톤과 동일.
        const seatWidthBase = 108.0;
        const seatHeightBase = 128.0;
        final seatWidth = seatWidthBase * boardScale;
        final seatHeight = seatHeightBase * boardScale;
        final playerCount = players.length;
        // 4인은 티츄 좌석 순서(0=아래, 1=오른, 2=위, 3=왼)를 그대로 살려 4-corner.
        // 3인/2인은 SK 관전 규칙.
        final List<double> anglesDeg = playerCount >= 4
            ? const [90.0, 0.0, 270.0, 180.0]
            : playerCount == 3
            ? const [155.0, 270.0, 385.0]
            : playerCount == 2
            ? const [180.0, 360.0]
            : const [270.0];
        final centerX = width / 2;
        // 4인은 위/아래 대칭을 유지한 채 하단 손패 영역이 아래 좌석을
        // 가리지 않도록 링 중심을 위로 올린다 (0.39 ≈ 11% 상향).
        final centerY = playerCount >= 4
            ? height * 0.39
            : (isLandscape ? height * 0.48 : height * 0.50);
        // 좌/우 간격을 화면 가장자리 쪽으로 더 벌린다 — 안쪽 여백을 10→2 로
        // 줄이고 factor 0.44→0.48. 좁은 폰에서도 sideRadius 가 몇 dp 더 커짐.
        final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 2);
        final seatRadiusX = math.min(
          width * 0.48,
          math.min(width >= 700 ? 260.0 : 210.0, maxSeatRadiusX),
        );
        final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 6);
        final seatRadiusY = math.min(
          height * (isLandscape ? 0.40 : 0.42),
          math.min(height >= 700 ? 220.0 : 196.0, maxSeatRadiusY),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // 좌석 먼저 그리기 — 그래야 트릭이 프로필 사진 위로 얹힌다.
            for (int i = 0; i < playerCount && i < anglesDeg.length; i++) ...[
              () {
                final p = players[i] as Map<String, dynamic>;
                final angle = anglesDeg[i] * math.pi / 180;
                final seatLeft =
                    centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
                final seatTop =
                    centerY + seatRadiusY * math.sin(angle) - seatHeight / 2;
                return Positioned(
                  left: seatLeft,
                  top: seatTop,
                  width: seatWidth,
                  height: seatHeight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: seatWidth,
                      child: _buildPlayerSection(
                        game,
                        p,
                        currentPlayer,
                        ringMode: true,
                      ),
                    ),
                  ),
                );
              }(),
            ],
            // 중앙 트릭: Stack 마지막에 얹어 좌석 프로필 위로 그려진다.
            // IgnorePointer 로 감싸 아래 좌석의 탭이 그대로 통하게.
            Positioned.fill(
              child: IgnorePointer(
                child: Align(
                  alignment: playerCount >= 4
                      ? const Alignment(0, -0.36)
                      : Alignment(0, isLandscape ? 0.38 : 0.48),
                  child: _buildTrickArea(
                    currentTrick,
                    callRank: callRank,
                    players: players,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGameEndOverlay(
    GameService game,
    Map<String, dynamic> scores,
    List players,
  ) {
    final teamA = (scores['teamA'] as num?)?.toInt() ?? 0;
    final teamB = (scores['teamB'] as num?)?.toInt() ?? 0;
    final l10n = L10n.of(context);
    // 팀 이름을 "Team A/B" 로 노출하지 않고 팀 색으로. 파란=A, 빨간=B.
    // 무승부는 별도 처리.
    final aWins = teamA > teamB;
    final bWins = teamB > teamA;
    final winnerText = aWins
        ? l10n.spectatorBlueTeamWin
        : bWins
        ? l10n.spectatorRedTeamWin
        : l10n.spectatorDraw;
    final winnerColor = aWins
        ? const Color(0xFF4A90D9)
        : bWins
        ? const Color(0xFFD24B4B)
        : const Color(0xFF6A5A52);

    final teamAPlayers = players
        .where((p) => p is Map && (p['team']?.toString() ?? '') == 'A')
        .cast<Map>()
        .toList();
    final teamBPlayers = players
        .where((p) => p is Map && (p['team']?.toString() ?? '') == 'B')
        .cast<Map>()
        .toList();

    // 플레이어 화면의 결과 팝업과 같은 톤 — 판을 검게 덮는 대신 흐리게
    // 하고, 상자를 겹쳐 그리는 대신 구분선으로 영역만 나눈다.
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        color: const Color(0x40000000),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  aWins || bWins ? Icons.emoji_events : Icons.handshake,
                  size: 34,
                  color: winnerColor,
                ),
                const SizedBox(height: 8),
                Text(
                  winnerText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    color: winnerColor,
                  ),
                ),
                const SizedBox(height: 18),
                // 두 팀을 상자 없이 나란히. 진 쪽은 살짝 덜어내는 것으로
                // 충분하다 — 테두리를 굵게 두르면 축하가 아니라 경고처럼
                // 보인다.
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _gameEndTeamColumn(
                          game: game,
                          teamPlayers: teamAPlayers,
                          score: teamA,
                          color: const Color(0xFF007AFF),
                          dimmed: bWins,
                        ),
                      ),
                      Container(width: 1, color: const Color(0xFFE5E5EA)),
                      Expanded(
                        child: _gameEndTeamColumn(
                          game: game,
                          teamPlayers: teamBPlayers,
                          score: teamB,
                          color: const Color(0xFFFF3B30),
                          dimmed: aWins,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(height: 0.5, color: const Color(0xFFE5E5EA)),
                const SizedBox(height: 12),
                Text(
                  l10n.spectatorAutoReturn,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gameEndTeamColumn({
    required GameService game,
    required List<Map> teamPlayers,
    required int score,
    required Color color,
    required bool dimmed,
  }) {
    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Flexible 로 감싸 좁은 폰(320dp)에서도 두 멤버가 칸 폭에
                // 균등하게 들어가도록.
                for (int i = 0; i < teamPlayers.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Flexible(
                    child: _buildGameEndMember(game, teamPlayers[i], color),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$score',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                letterSpacing: -1,
                color: color,
                // 자릿수가 달라도 두 칸이 흔들리지 않게.
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameEndMember(GameService game, Map player, Color color) {
    final name = (player['name'] ?? '').toString();
    final isBot = player['isBot'] == true;
    // 폭 상한만 잡고(52) 이름은 셀 폭에 맞춰 elipsize. 좁은 폰에서 두 멤버 +
    // 간격이 팀 카드의 내부 폭을 넘지 않도록 40dp 아바타로.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 52),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProfileAvatar(
            photoUrl: game.resolvePhotoUrl(player['photoUrl'] as String?),
            size: 40,
            blocked: game.blockedUsers.contains(name),
            fallback: isBot
                ? BotAvatar(size: 40, name: name)
                : DefaultAvatar(size: 40),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            // 이름은 중립색. 팀 색은 아래 점수 하나로 충분하고, 넷이 다
            // 색 글씨면 어느 쪽이 이겼는지가 오히려 안 보인다.
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF3C3C43),
            ),
          ),
        ],
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
                    // 좁아지면 순서대로 버린다: '관전 중' 글씨 → 목표 점수 →
                    // (마지막 수단) 라운드·단계 줄임표. 남는 폭을 아는 자리에서
                    // 실제 글자 폭을 재서 정하므로, 어느 언어든 넘치지 않고
                    // 무엇이 먼저 사라질지도 정해져 있다.
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          const watchStyle = TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4A4080),
                          );
                          const phaseStyle = TextStyle(
                            color: Color(0xFF8A7E78),
                            fontSize: 12,
                          );
                          const targetStyle = TextStyle(
                            color: Color(0xFFA89C96),
                            fontSize: 11,
                          );
                          final watchText = L10n.of(context).spectatorWatching;
                          final phaseText = 'R$round | ${_getPhaseText(phase)}';
                          final targetText = targetScore == null
                              ? ''
                              : L10n.of(
                                  context,
                                ).spectatorTargetScore(targetScore);

                          // 칩 = 좌우 여백 16 + 눈 12 + (여백 4 + 글씨)
                          const chipBase = 16.0 + 12.0;
                          final watchW = _textWidth(watchText, watchStyle);
                          final phaseW = _textWidth(phaseText, phaseStyle);
                          final targetW = targetText.isEmpty
                              ? 0.0
                              : _textWidth(targetText, targetStyle);
                          final avail = box.maxWidth;

                          final wantAll =
                              chipBase +
                              4 +
                              watchW +
                              8 +
                              phaseW +
                              (targetW > 0 ? 6 + targetW : 0);
                          final showWatchLabel = wantAll <= avail;
                          final chipW =
                              chipBase + (showWatchLabel ? 4 + watchW : 0);
                          final showTarget =
                              targetW > 0 &&
                              chipW + 8 + phaseW + 6 + targetW <= avail;

                          return Row(
                            children: [
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
                                    if (showWatchLabel) ...[
                                      const SizedBox(width: 4),
                                      Text(watchText, style: watchStyle),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  phaseText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: phaseStyle,
                                ),
                              ),
                              if (showTarget) ...[
                                const SizedBox(width: 6),
                                Text(targetText, style: targetStyle),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
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
    bool compact = false,
    bool ringMode = false,
  }) {
    final playerId = (player['id'] ?? '').toString();
    final name = player['name'] ?? '';
    final canSeeCards = player['canSeeCards'] == true;
    final isCurrentTurn = playerId == currentPlayerId;
    final hasFinished = player['hasFinished'] ?? false;
    final finishPosition = player['finishPosition'] ?? 0;
    final cardCount = ((player['cardCount'] as num?) ?? 0).toInt();
    final hasSmallTichu = player['hasSmallTichu'] ?? false;
    final hasLargeTichu = player['hasLargeTichu'] ?? false;
    final connected = player['connected'] ?? true;

    // 카드 보기 상태 — SK 관전과 동일. 좌석 사진에 눈 아이콘 뱃지로 표시.
    final isPending = game.pendingCardViewRequests.contains(playerId);
    final isApproved = game.approvedCardViews.contains(playerId) && canSeeCards;
    final isViewing = _viewingPlayerId == playerId && isApproved;

    // Faint team tint as the slot background (replaces the removed dot
    // indicator) so spectators can still tell which team each player is on
    // at a glance. Team A → cool blue, Team B → warm rose.
    // Ring 모드에선 배경 상자 자체를 없앤다 (사진이 좌석의 가장자리).
    final team = player['team']?.toString() ?? '';
    final slotBg = team == 'A'
        ? const Color(0xFFE9F2FB)
        : team == 'B'
        ? const Color(0xFFFBECEF)
        : Colors.white.withValues(alpha: 0.98);

    final isBot = player['isBot'] == true;
    // Web has room to spare and no touch-target minimums to respect, so it
    // gets a bump — the native sizes below were tuned for a phone screen and
    // read as noticeably small on a desktop-width browser tab.
    final webBoost = kIsWeb ? 1.35 : 1.0;
    final avatarSize =
        ((ringMode ? (compact ? 56 : 72) : (compact ? 44 : 56)) * webBoost)
            .toDouble();
    // 좌석 탭: 아직 승인 전이면 패 보기 요청, 승인 후엔 하단 손패 영역에
    // 이 사람의 패를 열거나 닫는다. 프로필 다이얼로그는 롱프레스로 이동
    // (SK 관전과 동일).
    //
    // 손패를 다 턴 사람도 똑같이 다룬다. 예전에는 눈 표시를 감추고 탭을
    // 프로필로 돌렸는데, 한 사람이 나가자마자 그 자리만 규칙이 달라져서
    // 눌러도 아무 일이 없는 것처럼 보였다. 열면 "남은 패 없음" 이 뜬다.
    void onSeatTap() {
      if (isApproved) {
        setState(() {
          _viewingPlayerId = _viewingPlayerId == playerId ? null : playerId;
        });
      } else if (isPending) {
        setState(() => _viewingPlayerId = playerId);
      } else {
        _cardViewRequestTimer?.cancel();
        game.requestCardView(playerId);
        setState(() => _viewingPlayerId = playerId);
        _cardViewRequestTimer = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          game.expireCardViewRequest(playerId);
        });
      }
    }

    return GestureDetector(
      onTap: onSeatTap,
      onLongPress: () => _showPlayerProfileDialog(name, game, isBot: isBot),
      child: _wrapWithBubble(
        name,
        Container(
          margin: ringMode ? EdgeInsets.zero : EdgeInsets.all(compact ? 2 : 4),
          padding: ringMode ? EdgeInsets.zero : EdgeInsets.all(compact ? 6 : 8),
          decoration: ringMode
              ? const BoxDecoration()
              : BoxDecoration(
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
              // 사진에 눈 아이콘 뱃지 (우측 상단) — 패보기 상태를 표시.
              // 현재 턴/보는 중일 때는 사진 자체 테두리로 강조.
              Padding(
                padding: EdgeInsets.only(bottom: compact ? 2 : 3),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    ProfileAvatar(
                      photoUrl: game.resolvePhotoUrl(
                        player['photoUrl'] as String?,
                      ),
                      size: avatarSize,
                      blocked: game.blockedUsers.contains(name),
                      border: (isCurrentTurn || isViewing)
                          ? Border.all(
                              color: isViewing
                                  ? const Color(0xFF64B5F6)
                                  : const Color(0xFFE6C86A),
                              width: 1.5,
                            )
                          : null,
                      fallback: isBot
                          // showBadge 없이 봇 아바타만 (봇 마크 제거).
                          ? BotAvatar(size: avatarSize, name: name)
                          : DefaultAvatar(size: avatarSize),
                    ),
                    // 다 턴 자리에도 남긴다 — onSeatTap 주석 참고.
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isApproved
                                ? const Color(0xFF64B5F6)
                                : const Color(0xFFE0D8D4),
                          ),
                        ),
                        child: Icon(
                          isPending
                              ? Icons.schedule
                              : isApproved
                              ? Icons.visibility
                              : Icons.visibility_outlined,
                          size: 12,
                          color: isPending
                              ? const Color(0xFFFFB74D)
                              : isApproved
                              ? const Color(0xFF64B5F6)
                              : const Color(0xFF8A7A72).withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
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
              // 남은 장수는 카드 뒷면으로 보여준다 — 게임 화면 좌석과 같은
              // 스트립이다. 실제 패는 하단 _buildSpectatorHandArea 에서
              // 열어보지만, 몇 장 남았는지는 판을 훑을 때 바로 읽혀야 한다.
              // (관전에는 이게 아예 없어서 라지티츄 단계에 여덟 장을 쥔 게
              // 화면 어디에도 안 나왔다.)
              if (!hasFinished && cardCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _compactHandBacks(cardCount, compact: compact),
                ),
              // 여기서는 탈락 상태만 표시.
              if (hasFinished)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    L10n.of(context).spectatorFinished,
                    style: TextStyle(
                      color: const Color(0xFF9A8E8A),
                      fontSize: compact ? 9 : 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 좌석 아래에 얹는 카드 뒷면 스트립. 게임 화면의
  /// `_buildCompactHandBacks` 와 같은 모양 — 폭이 좁으니 겹쳐 그리고,
  /// 장수는 오른쪽 끝 배지로 읽는다.
  Widget _compactHandBacks(int count, {required bool compact}) {
    // Web 부스트는 프로필 사진과 같은 비율 — 이 스트립도 그만큼 작아 보였다.
    final webBoost = kIsWeb ? 1.35 : 1.0;
    final scale = (compact ? 0.85 : 1.0) * webBoost;
    final cardW = 14.0 * scale;
    final cardH = 20.0 * scale;
    const double preferredStep = 4.0;
    final double maxTotalW = 60.0 * webBoost;
    final double step = count <= 1
        ? preferredStep * scale
        : (math
                  .min(preferredStep, (maxTotalW - 14.0) / (count - 1))
                  .clamp(2.0, preferredStep) *
              scale);
    final totalW = cardW + step * (count - 1);
    // 우측 상단 카드에 살짝 겹치는 카운트 뱃지 — 게임 화면과 동일. 주석은
    // 예전부터 "장수는 배지로 읽는다"고 적혀 있었는데 실제 배지는 빠져
    // 있었다 — 몇 장 남았는지 셀 방법이 카드를 직접 세는 것뿐이었다.
    final double badgeSize = 18.0 * scale;
    return SizedBox(
      width: totalW,
      height: cardH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < count; i++)
            Positioned(
              left: i * step,
              child: PlayingCard(
                cardId: '',
                isFaceUp: false,
                width: cardW,
                height: cardH,
                isInteractive: false,
              ),
            ),
          Positioned(
            right: -badgeSize * 0.35,
            top: -badgeSize * 0.35,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF5A4038),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11 * scale,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 글자가 실제로 차지할 폭. 상태 줄에서 무엇을 먼저 버릴지 정하는 데
  /// 쓴다 — Flex 는 남는 자리를 나눠줄 뿐, "이걸 먼저 지워라" 를 모른다.
  double _textWidth(String text, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      // 기기 글자 크기 설정을 그대로 태운다. 이걸 빼면 글자를 키워 쓰는
      // 사람에게는 실제보다 좁게 재서, 넘치지 않게 하려고 만든 계산이
      // 도로 넘치게 만든다.
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return tp.width;
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

  Widget _buildHorizontalCards(List cards, {bool compact = false}) {
    // 하단 손패 영역용. 카드는 게임 화면 트릭 톤(44×62), overlap 은 숫자·문양이
    // 읽히도록 넉넉하게(카드 폭의 약 66%만 겹침). 14장을 다 펼치면 가로가
    // 폭 캡을 넘으므로 FittedBox 로 전체를 스케일다운해 잘림 없이 축소.
    final cardWidth = (compact ? 32.0 : 44.0) * _s;
    final cardHeight = (compact ? 45.0 : 62.0) * _s;
    final overlap = (compact ? 24.0 : 30.0) * _s;

    final totalWidth = cardWidth + (cards.length - 1) * overlap;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: SizedBox(
        height: cardHeight,
        width: totalWidth,
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
      // 배경 상자 없이 텍스트만. Center 래퍼도 뺀다 — 부모 Align 이 위치를
      // 담당하는데 Center 가 다시 부모를 꽉 채워 Align y 값이 무력화됐다.
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 8 : 10,
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
    // 이름의 팀 색상만 유지, 배경/테두리 상자는 제거 — 게임 화면과 동일 톤.
    final nameColor = isBlue
        ? const Color(0xFF4A90D9)
        : const Color(0xFFD94A5A);

    // 외곽 Center 제거 — 부모 Align 이 위치를 잡도록.
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
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
    );
  }

  Widget _buildOverlappedCards(
    List cards, {
    bool compact = false,
    bool forceSingleRow = false,
    String combo = '',
    double comboValue = 0,
  }) {
    // 트릭 카드 크기: 하단 손패 톤(44×62)에 맞춰 상향. 겹침도 그에 맞게.
    final double cardW = (compact ? 30 : 44) * _s;
    final double cardH = (compact ? 42 : 62) * _s;
    final double minOverlap = (compact ? 12 : 24) * _s;
    final double maxOverlap = (compact ? 22 : 34) * _s;

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

    // 3장 이하만 나란히 배열, 4장부터는 overlap 경로로 태워 살짝 겹친다
    // (4장 연속페어 4455 예시). 겹침량은 아래 LayoutBuilder 의 clamp 로 통제.
    if (cards.length <= 3) {
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
        // 긴 스트레이트/피 (7장 이상) 는 억지로 한 줄에 밀어넣지 말고 두 줄로.
        // 한 줄이면 카드가 너무 겹쳐 숫자·문양이 안 보인다. landscape compact 에서
        // 강제 한 줄이 필요한 경로는 forceSingleRow 로 계속 예외.
        final wantTwoRows = !forceSingleRow && cards.length >= 7;

        if (!wantTwoRows && (neededOverlap >= minOverlap || forceSingleRow)) {
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
