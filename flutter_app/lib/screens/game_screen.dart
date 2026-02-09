import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import 'lobby_screen.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final Set<String> _selectedCards = {};

  // 카드 교환용 상태
  final Map<String, String> _exchangeAssignments = {}; // position -> cardId
  final Map<String, String> _exchangeGiven = {}; // position -> cardId
  List<String> _preExchangeHand = [];
  bool _exchangeSummaryShown = false;

  // 채팅
  bool _chatOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 로그인 후 차단 목록 요청
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameService>().requestBlockedUsers();
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _toggleCard(String cardId, {bool singleSelect = false}) {
    setState(() {
      if (_selectedCards.contains(cardId)) {
        _selectedCards.remove(cardId);
      } else {
        if (singleSelect) {
          _selectedCards.clear();
        }
        _selectedCards.add(cardId);
      }
    });
  }

  void _playCards() {
    if (_selectedCards.isEmpty) return;

    // Bird 포함 시 콜 선택 먼저
    if (_selectedCards.contains('special_bird')) {
      _showBirdCallDialog();
      return;
    }

    context.read<GameService>().playCards(_selectedCards.toList());
    setState(() => _selectedCards.clear());
  }

  void _showBirdCallDialog() {
    final ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('콜할 숫자 선택'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: ranks.map((rank) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.read<GameService>().playCards(
                      _selectedCards.toList(),
                      callRank: rank,
                    );
                    setState(() => _selectedCards.clear());
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(48, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: Text(rank),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() => _selectedCards.clear());
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6A5A52),
              ),
              child: const Text('취소 (다른 카드 내기)'),
            ),
          ],
        ),
      ),
    );
  }

  void _passTurn() {
    context.read<GameService>().passTurn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF8F4F6),
              Color(0xFFEDE6F0),
              Color(0xFFE0ECF6),
            ],
          ),
        ),
        child: SafeArea(
          child: Consumer<GameService>(
            builder: (context, game, _) {
              final state = game.gameState;
              if (state == null) {
                return const Center(child: CircularProgressIndicator());
              }

              _maybeShowExchangeSummary(state);

              return Stack(
                children: [
                  if (_tichuOverlayColor(state) != null)
                    Positioned.fill(
                      child: Container(
                        color: _tichuOverlayColor(state),
                      ),
                    ),
                  Column(
                    children: [
                      // Top area - partner
                      _buildPartnerArea(state),

                      // Middle area - opponents + center
                      Expanded(
                        child: _buildMiddleArea(state, game),
                      ),

                      // Bottom area - my hand
                      _buildBottomArea(state, game),
                    ],
                  ),

                  // Dialogs/Panels
                  if (state.phase == 'large_tichu_phase' &&
                      !state.largeTichuResponded)
                    _buildLargeTichuDialog(game),

                  if (state.phase == 'card_exchange' && !state.exchangeDone)
                    _buildExchangeDialog(state, game),

                  if (state.dragonPending) _buildDragonDialog(state, game),

                  if (state.needsToCallRank) _buildCallRankDialog(game),

                  if (state.phase == 'round_end' || state.phase == 'game_end')
                    _buildRoundEndDialog(state, game),

                  // Error message banner
                  if (game.errorMessage != null)
                    _buildErrorBanner(game.errorMessage!),

                  // Spectator card view requests
                  if (game.incomingCardViewRequests.isNotEmpty)
                    _buildCardViewRequestPopup(game),

                  // Menu button (top right)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildMenuButton(game),
                  ),

                  // Chat button (top right, below menu)
                  Positioned(
                    top: 8,
                    right: 56,
                    child: _buildChatButton(game),
                  ),

                  // Chat panel
                  if (_chatOpen) _buildChatPanel(game),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuButton(GameService game) {
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ],
        ),
        child: const Icon(
          Icons.menu,
          color: Color(0xFF5A4038),
          size: 20,
        ),
      ),
      onSelected: (value) {
        if (value == 'leave') {
          _showLeaveGameDialog(game);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          value: 'leave',
          child: Row(
            children: [
              Icon(Icons.exit_to_app, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('게임 나가기', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatButton(GameService game) {
    final unreadCount = game.chatMessages.where((m) =>
      !game.isBlocked(m['sender'] as String? ?? '')
    ).length;

    return GestureDetector(
      onTap: () => setState(() => _chatOpen = !_chatOpen),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _chatOpen
              ? const Color(0xFF64B5F6)
              : Colors.white.withValues(alpha: 0.8),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(
          Icons.chat_bubble_outline,
          color: _chatOpen ? Colors.white : const Color(0xFF5A4038),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildChatPanel(GameService game) {
    return Positioned(
      top: 50,
      right: 8,
      width: 280,
      height: 350,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF64B5F6),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  const Text(
                    '채팅',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _chatOpen = false),
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // Messages
            Expanded(
              child: ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.all(8),
                itemCount: game.chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = game.chatMessages[index];
                  final sender = msg['sender'] as String? ?? '';
                  final message = msg['message'] as String? ?? '';
                  final isMe = sender == game.playerName;
                  final isBlocked = game.isBlocked(sender);

                  if (isBlocked) return const SizedBox.shrink();

                  return _buildChatBubble(sender, message, isMe, game);
                },
              ),
            ),
            // Input
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      decoration: const InputDecoration(
                        hintText: '메시지 입력...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _sendChatMessage(game),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sendChatMessage(game),
                    icon: const Icon(Icons.send, color: Color(0xFF64B5F6)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String sender, String message, bool isMe, GameService game) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: isMe ? null : () => _showUserActionDialog(sender, game),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFFE0E0E0),
                child: Text(
                  sender.isNotEmpty ? sender[0] : '?',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        sender,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF64B5F6) : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      message,
                      style: TextStyle(
                        fontSize: 14,
                        color: isMe ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendChatMessage(GameService game) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    game.sendChatMessage(message);
    _chatController.clear();
    // Scroll to bottom after sending
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showUserActionDialog(String nickname, GameService game) {
    final isBlocked = game.isBlocked(nickname);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              nickname,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
            const SizedBox(height: 20),
            _buildActionButton(
              icon: Icons.person_add,
              label: '친구 추가',
              color: const Color(0xFF81C784),
              onTap: () {
                Navigator.pop(context);
                game.addFriendAction(nickname);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('친구 요청을 보냈습니다')),
                );
              },
            ),
            const SizedBox(height: 10),
            _buildActionButton(
              icon: isBlocked ? Icons.check_circle : Icons.block,
              label: isBlocked ? '차단 해제' : '차단하기',
              color: isBlocked ? const Color(0xFF64B5F6) : const Color(0xFFFF8A65),
              onTap: () {
                Navigator.pop(context);
                if (isBlocked) {
                  game.unblockUserAction(nickname);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('차단이 해제되었습니다')),
                  );
                } else {
                  game.blockUserAction(nickname);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('차단되었습니다')),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            _buildActionButton(
              icon: Icons.flag,
              label: '신고하기',
              color: const Color(0xFFE57373),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog(nickname, game);
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  void _showReportDialog(String nickname, GameService game) {
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$nickname 신고'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('신고 사유를 입력해주세요'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '신고 사유',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(context);
              game.reportUserAction(nickname, reason);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('신고가 접수되었습니다')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE57373),
            ),
            child: const Text('신고'),
          ),
        ],
      ),
    );
  }

  void _showLeaveGameDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게임 나가기'),
        content: const Text('정말 게임을 나가시겠습니까?\n게임 중 나가면 팀에 피해가 됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.leaveGame();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LobbyScreen()),
              );
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    // 콜 관련 에러인지 확인
    final isCallError = message.contains('Call') || message.contains('콜');
    final displayMessage = isCallError
        ? '콜된 숫자를 먼저 내야 합니다!'
        : message;

    return Positioned(
      bottom: 200,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE4E4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF6B6B)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFCC4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                displayMessage,
                style: const TextStyle(
                  color: Color(0xFFCC4444),
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardViewRequestPopup(GameService game) {
    final request = game.incomingCardViewRequests.first;
    final spectatorNickname = request['spectatorNickname'] ?? '관전자';
    final spectatorId = request['spectatorId'] ?? '';

    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility, color: Color(0xFF6A6090)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$spectatorNickname님이 패 보기를 요청했습니다',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A4080),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => game.respondCardViewRequest(spectatorId, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCC6666),
                      side: const BorderSide(color: Color(0xFFCC6666)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('거부'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => game.respondCardViewRequest(spectatorId, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A9BD1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('허가'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerArea(GameStateData state) {
    final partner = _firstWhereOrNull(
      state.players,
      (p) => p.position == 'partner',
    );
    final isPartnerTurn = partner?.id == state.currentPlayer;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildTurnName(
            name: partner?.name ?? '파트너',
            isTurn: isPartnerTurn,
            badge: _tichuBadgeForPlayer(partner),
            connected: partner?.connected ?? true,
          ),
          const SizedBox(height: 4),
          Text(
            _getPlayerInfo(partner),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8A7A72),
            ),
          ),
          const SizedBox(height: 8),
          // Card backs
          _buildOverlappedHand(
            count: partner?.cardCount ?? 0,
            cardWidth: 30,
            cardHeight: 42,
            overlap: 18,
            maxVisible: 14,
          ),
        ],
      ),
    );
  }

  Widget _buildMiddleArea(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final right = _firstWhereOrNull(state.players, (p) => p.position == 'right');
    final isLeftTurn = left?.id == state.currentPlayer;
    final isRightTurn = right?.id == state.currentPlayer;

    return Row(
      children: [
        // Left player
        SizedBox(
          width: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTurnName(
                name: left?.name ?? '좌측',
                isTurn: isLeftTurn,
                fontSize: 12,
                badge: _tichuBadgeForPlayer(left),
                connected: left?.connected ?? true,
              ),
              Text(
                _getPlayerInfo(left),
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A7A72)),
              ),
              const SizedBox(height: 6),
              _buildOverlappedHandVertical(
                count: left?.cardCount ?? 0,
                cardWidth: 24,
                cardHeight: 34,
                overlap: 26,
                maxVisible: 14,
              ),
            ],
          ),
        ),

        // Center area
        Expanded(
          child: _buildCenterArea(state, game),
        ),

        // Right player
        SizedBox(
          width: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTurnName(
                name: right?.name ?? '우측',
                isTurn: isRightTurn,
                fontSize: 12,
                badge: _tichuBadgeForPlayer(right),
                connected: right?.connected ?? true,
              ),
              Text(
                _getPlayerInfo(right),
                style: const TextStyle(fontSize: 10, color: Color(0xFF8A7A72)),
              ),
              const SizedBox(height: 6),
              _buildOverlappedHandVertical(
                count: right?.cardCount ?? 0,
                cardWidth: 24,
                cardHeight: 34,
                overlap: 26,
                maxVisible: 14,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCenterArea(GameStateData state, GameService game) {
    return Center(
      child: Container(
        width: 240,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Phase & Turn info
            Text(
              _getPhaseName(state.phase),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
              textAlign: TextAlign.center,
            ),
            if (state.phase == 'playing') ...[
              const SizedBox(height: 3),
              Text(
                state.isMyTurn ? '내 턴!' : '${_getCurrentPlayerName(state)}의 턴',
                style: TextStyle(
                  fontSize: 11,
                  color: state.isMyTurn
                      ? const Color(0xFFE6A800)
                      : const Color(0xFF8A7A72),
                  fontWeight:
                      state.isMyTurn ? FontWeight.bold : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Call rank display
            if (state.callRank != null && state.callRank!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                '콜: ${state.callRank}',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFCC6666),
                ),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 4),

            if (game.dogPlayActive)
              _buildDogPlayedBanner(game.dogPlayPlayerName),

            if (game.dogPlayActive) const SizedBox(height: 4),

            // Latest trick only
            if (state.currentTrick.isNotEmpty)
              _buildLatestTrick(state),

            const SizedBox(height: 4),

            // Score display
            Text(
              '팀A: ${state.totalScores['teamA']} | 팀B: ${state.totalScores['teamB']}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF6A5A52),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDogPlayedBanner(String playerName) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6DCE8)),
      ),
      child: Column(
        children: [
          Text(
            playerName.isNotEmpty ? '$playerName가 개를 냈어' : '개가 나왔어',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF8A7A72),
            ),
          ),
          const SizedBox(height: 4),
          const PlayingCard(
            cardId: 'special_dog',
            width: 32,
            height: 45,
            isInteractive: false,
          ),
        ],
      ),
    );
  }

  Widget _buildLatestTrick(GameStateData state) {
    final lastPlay = state.currentTrick.last;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6DCE8)),
      ),
      child: Column(
        children: [
          Text(
            '${lastPlay.playerName}가 낸 패',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF8A7A72),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 3,
            runSpacing: 3,
            children: lastPlay.cards
                .map(
                  (cardId) => PlayingCard(
                    cardId: cardId,
                    width: 36,
                    height: 50,
                    isInteractive: false,
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomArea(GameStateData state, GameService game) {
    final isMyTurn = state.isMyTurn;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // My status (no name)
          if (_tichuBadgeForSelf(state) != null || isMyTurn) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isMyTurn)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF2B3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE6C86A)),
                    ),
                    child: const Text(
                      '내 턴!',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ),
                if (isMyTurn && _tichuBadgeForSelf(state) != null)
                  const SizedBox(width: 8),
                if (_tichuBadgeForSelf(state) != null)
                  _tichuBadgeForSelf(state)!,
              ],
            ),
            const SizedBox(height: 12),
          ],

          // My hand - two rows (split in half)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _buildHandRows(state),
          ),
          const SizedBox(height: 8),

          // Action buttons (stable layout)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: (state.phase == 'playing' &&
                        state.isMyTurn &&
                        _selectedCards.isNotEmpty)
                    ? _playCards
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDAF3E1),
                  foregroundColor: const Color(0xFF2F5A40),
                  disabledBackgroundColor: const Color(0xFFCAC3BF),
                  disabledForegroundColor: const Color(0xFF7A6E68),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('내기'),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: (state.phase == 'playing' &&
                        state.isMyTurn &&
                        state.currentTrick.isNotEmpty)
                    ? _passTurn
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF3EDE8),
                  foregroundColor: const Color(0xFF5A4E48),
                  disabledBackgroundColor: const Color(0xFFCFC7C2),
                  disabledForegroundColor: const Color(0xFF7D736E),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('패스'),
              ),
              const SizedBox(width: 12),
              if (state.canDeclareSmallTichu &&
                  !state.players.any((p) => p.hasLargeTichu))
                ElevatedButton(
                  onPressed: () => game.declareSmallTichu(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFE4B5),
                    foregroundColor: const Color(0xFF8B6914),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('스몰티츄'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLargeTichuDialog(GameService game) {
    return _buildTopBanner(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          const Text(
            '라지티츄?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          ElevatedButton(
            onPressed: () => game.declareLargeTichu(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('선언!'),
          ),
          OutlinedButton(
            onPressed: () => game.passLargeTichu(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text('패스'),
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeDialog(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final partner = _firstWhereOrNull(state.players, (p) => p.position == 'partner');
    final right = _firstWhereOrNull(state.players, (p) => p.position == 'right');

    final selectedCard = _selectedCards.isNotEmpty ? _selectedCards.first : null;
    final assignedCount = _exchangeAssignments.length;

    return _buildTopBanner(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            selectedCard != null ? '카드를 줄 상대 선택' : '교환할 카드 선택 ($assignedCount/3)',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildExchangeButton('left', left?.name ?? '좌측', selectedCard),
              _buildExchangeButton('partner', partner?.name ?? '파트너', selectedCard),
              _buildExchangeButton('right', right?.name ?? '우측', selectedCard),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_exchangeAssignments.isNotEmpty)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _exchangeAssignments.clear();
                      _selectedCards.clear();
                    });
                  },
                  child: const Text('초기화'),
                ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: assignedCount == 3
                    ? () {
                        _preExchangeHand = List<String>.from(state.myCards);
                        _exchangeGiven
                          ..clear()
                          ..addAll(_exchangeAssignments);
                        _exchangeSummaryShown = false;
                        game.exchangeCards(
                          _exchangeAssignments['left']!,
                          _exchangeAssignments['partner']!,
                          _exchangeAssignments['right']!,
                        );
                        setState(() {
                          _exchangeAssignments.clear();
                          _selectedCards.clear();
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC7E6D0),
                  foregroundColor: const Color(0xFF3A5A40),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('교환 완료'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeButton(String position, String name, String? selectedCard) {
    final assignedCard = _exchangeAssignments[position];
    final isAssigned = assignedCard != null;
    final canAssign = selectedCard != null && !isAssigned && !_exchangeAssignments.containsValue(selectedCard);

    return GestureDetector(
      onTap: canAssign
          ? () {
              setState(() {
                _exchangeAssignments[position] = selectedCard;
                _selectedCards.clear();
              });
            }
          : isAssigned
              ? () {
                  setState(() {
                    _exchangeAssignments.remove(position);
                  });
                }
              : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isAssigned
              ? const Color(0xFFC7E6D0)
              : canAssign
                  ? const Color(0xFFE8F4FF)
                  : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: canAssign ? const Color(0xFF4D99FF) : const Color(0xFFDDD0CC),
            width: canAssign ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isAssigned ? const Color(0xFF3A5A40) : const Color(0xFF5A4038),
              ),
            ),
            if (isAssigned) ...[
              const SizedBox(height: 4),
              PlayingCard(
                cardId: assignedCard,
                width: 28,
                height: 39,
                isInteractive: false,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDragonDialog(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final right = _firstWhereOrNull(state.players, (p) => p.position == 'right');
    final leftName = left?.name ?? '좌측';
    final rightName = right?.name ?? '우측';
    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '용 트릭을 누구에게 주시겠습니까?',
            style: TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              ElevatedButton(
                onPressed: () => game.dragonGive('left'),
                child: Text(leftName),
              ),
              ElevatedButton(
                onPressed: () => game.dragonGive('right'),
                child: Text(rightName),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCallRankDialog(GameService game) {
    final ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '콜할 숫자를 선택하세요',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: ranks.map((rank) {
              return ElevatedButton(
                onPressed: () => game.callRank(rank),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text(rank),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundEndDialog(GameStateData state, GameService game) {
    final isGameEnd = state.phase == 'game_end';
    String title = isGameEnd ? '게임 종료!' : '라운드 종료!';

    if (isGameEnd) {
      final teamA = state.totalScores['teamA'] ?? 0;
      final teamB = state.totalScores['teamB'] ?? 0;
      title = teamA > teamB ? '팀A 승리!' : '팀B 승리!';
    }

    return _buildDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          if (state.lastRoundScores.isNotEmpty)
            Text(
              '이번 라운드: 팀A ${state.lastRoundScores['teamA']} | 팀B ${state.lastRoundScores['teamB']}',
              style: const TextStyle(fontSize: 14),
            ),
          const SizedBox(height: 8),
          Text(
            '총점: 팀A ${state.totalScores['teamA']} | 팀B ${state.totalScores['teamB']}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              if (isGameEnd) {
                game.leaveRoom();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LobbyScreen()),
                );
              } else {
                game.nextRound();
              }
            },
            child: Text(isGameEnd ? '로비로 돌아가기' : '다음 라운드'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBanner({required Widget child}) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildDialog({required Widget child}) {
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
          child: child,
        ),
      ),
    );
  }

  String _getPlayerInfo(Player? player) {
    if (player == null) return '';
    if (player.hasFinished) return '${player.finishPosition}등!';

    return '${player.cardCount}장';
  }

  String _getPhaseName(String phase) {
    switch (phase) {
      case 'large_tichu_phase':
        return '라지티츄 선언';
      case 'dealing_remaining_6':
        return '카드 분배 중';
      case 'card_exchange':
        return '카드 교환';
      case 'playing':
        return '게임 진행 중';
      case 'round_end':
        return '라운드 종료';
      case 'game_end':
        return '게임 종료';
      default:
        return phase;
    }
  }

  String _getCurrentPlayerName(GameStateData state) {
    if (state.currentPlayer == null) return '';
    final player = _firstWhereOrNull(
      state.players,
      (p) => p.id == state.currentPlayer,
    );
    return player?.name ?? '';
  }

  Widget _buildOverlappedHand({
    required int count,
    required double cardWidth,
    required double cardHeight,
    required double overlap,
    int maxVisible = 12,
  }) {
    final visible = count.clamp(0, maxVisible);
    final totalWidth = visible == 0
        ? 0.0
        : cardWidth + (visible - 1) * (cardWidth - overlap);

    return SizedBox(
      height: cardHeight,
      child: Center(
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            SizedBox(width: totalWidth, height: cardHeight),
            for (var i = 0; i < visible; i++)
              Positioned(
                left: i * (cardWidth - overlap),
                child: PlayingCard(
                  cardId: '',
                  isFaceUp: false,
                  width: cardWidth,
                  height: cardHeight,
                  isInteractive: false,
                ),
              ),
            if (count > visible)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE6DCE8)),
                  ),
                  child: Text(
                    '+${count - visible}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF8A7A72),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlappedHandVertical({
    required int count,
    required double cardWidth,
    required double cardHeight,
    required double overlap,
    int maxVisible = 8,
  }) {
    final visible = count.clamp(0, maxVisible);
    final totalHeight = visible == 0
        ? 0.0
        : cardHeight + (visible - 1) * (cardHeight - overlap);

    return SizedBox(
      width: cardWidth,
      height: totalHeight,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          for (var i = 0; i < visible; i++)
            Positioned(
              top: i * (cardHeight - overlap),
              child: PlayingCard(
                cardId: '',
                isFaceUp: false,
                width: cardWidth,
                height: cardHeight,
                isInteractive: false,
              ),
            ),
        ],
      ),
    );
  }

  Player? _firstWhereOrNull(
    Iterable<Player> players,
    bool Function(Player p) test,
  ) {
    for (final p in players) {
      if (test(p)) return p;
    }
    return null;
  }

  void _maybeShowExchangeSummary(GameStateData state) {
    if (_exchangeSummaryShown) return;
    if (!state.exchangeDone) return;
    if (_exchangeGiven.isEmpty || _preExchangeHand.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _exchangeSummaryShown) return;
      _exchangeSummaryShown = true;
      final leftName = _nameForPosition(state, 'left');
      final partnerName = _nameForPosition(state, 'partner');
      final rightName = _nameForPosition(state, 'right');

      final givenLeft = _exchangeGiven['left'];
      final givenPartner = _exchangeGiven['partner'];
      final givenRight = _exchangeGiven['right'];

      final removed = _preExchangeHand.where((c) {
        return c != givenLeft && c != givenPartner && c != givenRight;
      }).toList();
      final received = state.myCards.where((c) => !removed.contains(c)).toList();
      final receivedLeft = received.isNotEmpty ? received[0] : null;
      final receivedPartner = received.length > 1 ? received[1] : null;
      final receivedRight = received.length > 2 ? received[2] : null;

      showDialog(
        context: context,
        builder: (_) => _buildDialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '카드 교환 결과',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildExchangeSummaryRowLine([
                _ExchangeSummaryItem(leftName, givenLeft),
                _ExchangeSummaryItem(partnerName, givenPartner),
                _ExchangeSummaryItem(rightName, givenRight),
              ]),
              const SizedBox(height: 12),
              const Text(
                '받은 카드 (좌-파트너-우 순서)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              _buildExchangeSummaryRowLine([
                _ExchangeSummaryItem(leftName, receivedLeft),
                _ExchangeSummaryItem(partnerName, receivedPartner),
                _ExchangeSummaryItem(rightName, receivedRight),
              ]),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE8E0DC),
                  foregroundColor: const Color(0xFF6A5A52),
                ),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      );
    });
  }

  String _nameForPosition(GameStateData state, String position) {
    final p = _firstWhereOrNull(state.players, (pl) => pl.position == position);
    return p?.name ?? position;
  }

  Widget _buildExchangeSummaryRowLine(List<_ExchangeSummaryItem> items) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: items
          .where((i) => i.cardId != null)
          .map(
            (item) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A7A72),
                  ),
                ),
                const SizedBox(height: 4),
                PlayingCard(
                  cardId: item.cardId!,
                  width: 34,
                  height: 48,
                  isInteractive: false,
                ),
              ],
            ),
          )
          .toList(),
    );
  }

  Widget _buildTurnName({
    required String name,
    required bool isTurn,
    double fontSize = 14,
    Widget? badge,
    bool connected = true,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isTurn ? const Color(0xFFFFF2B3) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isTurn
            ? Border.all(color: const Color(0xFFE6C86A))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!connected)
            Container(
              margin: const EdgeInsets.only(right: 6),
              child: const Icon(
                Icons.wifi_off,
                size: 14,
                color: Colors.red,
              ),
            )
          else if (isTurn)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE6A800),
                shape: BoxShape.circle,
              ),
            ),
          Text(
            name,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: connected ? const Color(0xFF5A4038) : Colors.grey,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 6),
            badge,
          ],
        ],
      ),
    );
  }

  Widget? _tichuBadgeForPlayer(Player? player) {
    if (player == null) return null;
    if (player.hasLargeTichu) {
      return _tichuBadge(label: '라지', bg: const Color(0xFFFFD6D6), fg: const Color(0xFFB44A4A));
    }
    if (player.hasSmallTichu) {
      return _tichuBadge(label: '스몰', bg: const Color(0xFFDCEBFF), fg: const Color(0xFF3C6BB5));
    }
    return null;
  }

  Widget? _tichuBadgeForSelf(GameStateData state) {
    final me = _firstWhereOrNull(state.players, (p) => p.position == 'self');
    return _tichuBadgeForPlayer(me);
  }

  Widget _tichuBadge({
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  Color? _tichuOverlayColor(GameStateData state) {
    final anyLarge = state.players.any((p) => p.hasLargeTichu);
    final anySmall = state.players.any((p) => p.hasSmallTichu);
    if (anyLarge) return const Color(0x33FF6B6B);
    if (anySmall) return const Color(0x334BA3FF);
    return null;
  }

  Widget _buildHandRows(GameStateData state) {
    final cards = state.myCards;
    final isExchangePhase = state.phase == 'card_exchange' && !state.exchangeDone;

    // 교환 단계에서 이미 할당된 카드는 선택 불가
    bool isCardAssigned(String cardId) => _exchangeAssignments.containsValue(cardId);

    Widget buildCardWidget(String cardId, double cardWidth, double cardHeight) {
      final assigned = isCardAssigned(cardId);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Opacity(
          opacity: assigned ? 0.4 : 1.0,
          child: PlayingCard(
            cardId: cardId,
            width: cardWidth,
            height: cardHeight,
            isSelected: _selectedCards.contains(cardId),
            onTap: assigned ? null : () => _toggleCard(cardId, singleSelect: isExchangePhase),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalMargin = 16.0;
        final availableWidth = constraints.maxWidth - (horizontalMargin * 2);
        final perRow = cards.length <= 6 ? cards.length : (cards.length / 2).ceil();
        const cardPadding = 4.0; // 2px on each side
        final totalPadding = perRow * cardPadding;
        final cardWidth =
            ((availableWidth - totalPadding) / perRow).clamp(38.0, 50.0);
        final cardHeight = (cardWidth * 1.4).clamp(53.0, 70.0);

        List<Widget> rowWidgets(List<String> row) {
          return row.map((cardId) => buildCardWidget(cardId, cardWidth, cardHeight)).toList();
        }

        if (cards.length <= 6) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: rowWidgets(cards),
            ),
          );
        }

        final half = (cards.length / 2).ceil();
        final firstRow = cards.take(half).toList();
        final secondRow = cards.skip(half).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: horizontalMargin),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: rowWidgets(firstRow),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: rowWidgets(secondRow),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExchangeSummaryItem {
  final String name;
  final String? cardId;
  const _ExchangeSummaryItem(this.name, this.cardId);
}
