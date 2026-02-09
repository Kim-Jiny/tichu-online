import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import 'lobby_screen.dart';
import '../widgets/connection_overlay.dart';

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
  bool _exchangeSummaryShown = false;

  // 채팅
  bool _chatOpen = false;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // 턴 타이머
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  @override
  void initState() {
    super.initState();
    // 로그인 후 차단 목록 요청
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GameService>().requestBlockedUsers();
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    final state = context.read<GameService>().gameState;
    if (state == null || state.turnDeadline == null) {
      if (_remainingSeconds != 0) {
        setState(() => _remainingSeconds = 0);
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((state.turnDeadline! - now) / 1000).ceil().clamp(0, 999);
    if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
    }
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
    return ConnectionOverlay(
      child: Scaffold(
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
                // Room closed - go back to lobby
                if (game.currentRoomId.isEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LobbyScreen()),
                    );
                  });
                  return const Center(child: CircularProgressIndicator());
                }

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
                      _buildPartnerArea(state, game),

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

                  // Dragon given banner
                  if (game.dragonGivenMessage != null)
                    _buildDragonGivenBanner(game.dragonGivenMessage!),

                  // Timeout banner
                  if (game.timeoutPlayerName != null)
                    _buildTimeoutBanner(game.timeoutPlayerName!),

                  // Desertion banner
                  if (game.desertedPlayerName != null)
                    _buildDesertionBanner(game.desertedPlayerName!, game.desertedReason ?? 'leave'),

                  // Error message banner
                  if (game.errorMessage != null)
                    _buildErrorBanner(game.errorMessage!),

                  // Spectator card view requests
                  if (game.incomingCardViewRequests.isNotEmpty)
                    _buildCardViewRequestPopup(game),

                  // Card viewers (spectators watching my cards)
                  if (game.cardViewers.isNotEmpty)
                    _buildCardViewersChips(game),

                  // Countdown timer (top left)
                  if (_remainingSeconds > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: _remainingSeconds <= 10
                              ? const Color(0xFFFFE4E4)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _remainingSeconds <= 10
                                ? const Color(0xFFFF6B6B)
                                : const Color(0xFFCCCCCC),
                            width: _remainingSeconds <= 10 ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '${_remainingSeconds}초',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _remainingSeconds <= 10
                                ? const Color(0xFFCC4444)
                                : const Color(0xFF5A4038),
                          ),
                        ),
                      ),
                    ),

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
      ),
    );
  }

  Widget _buildMenuButton(GameService game) {
    return GestureDetector(
      onTap: () => _showLeaveGameDialog(game),
      child: Container(
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
          Icons.logout,
          color: Color(0xFFE53935),
          size: 20,
        ),
      ),
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

  void _showPlayerProfileDialog(String nickname, GameService game) {
    game.requestProfile(nickname);

    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<GameService>(
          builder: (ctx, game, _) {
            final profile = game.profileData;
            final isLoading = profile == null || profile['nickname'] != nickname;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFE0D8D4),
                    child: Text(
                      nickname.isNotEmpty ? nickname[0] : '?',
                      style: const TextStyle(fontSize: 18, color: Color(0xFF5A4038)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      nickname,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: isLoading
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _buildPlayerProfileContent(profile),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('닫기'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPlayerProfileContent(Map<String, dynamic> data) {
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) {
      return const Text('프로필을 찾을 수 없습니다');
    }

    final totalGames = profile['totalGames'] ?? 0;
    final wins = profile['wins'] ?? 0;
    final losses = profile['losses'] ?? 0;
    final rating = profile['rating'] ?? 1000;
    final winRate = profile['winRate'] ?? 0;
    final seasonRating = profile['seasonRating'] ?? 1000;
    final seasonGames = profile['seasonGames'] ?? 0;
    final seasonWins = profile['seasonWins'] ?? 0;
    final seasonLosses = profile['seasonLosses'] ?? 0;
    final seasonWinRate = profile['seasonWinRate'] ?? 0;
    final recentMatches = data['recentMatches'] as List<dynamic>? ?? [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Season rating
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F3FA),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4DFF2)),
          ),
          child: Column(
            children: [
              const Text(
                '시즌 랭킹전',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF7A6A95),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.emoji_events, color: Color(0xFFFFD54F), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '$seasonRating',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4A4080),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildProfileStatItem(
                    '전적',
                    '${seasonGames}전 ${seasonWins}승 ${seasonLosses}패',
                  ),
                  _buildProfileStatItem('승률', '$seasonWinRate%'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Stats
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildProfileStatItem('전적', '${totalGames}전 ${wins}승 ${losses}패'),
                  _buildProfileStatItem('승률', '$winRate%'),
                ],
              ),
            ],
          ),
        ),
        // Recent 5 matches
        if (recentMatches.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '최근 전적 (3)',
                style: TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
              ),
              const Spacer(),
              if (recentMatches.length > 3)
                TextButton(
                  onPressed: () => _showRecentMatchesDialog(recentMatches),
                  child: const Text('더보기'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Column(
            children: recentMatches.take(3).map<Widget>((match) {
              final won = match['won'] == true;
              final teamAScore = match['teamAScore'] ?? 0;
              final teamBScore = match['teamBScore'] ?? 0;
              final teamA = _formatTeam(match['playerA1'], match['playerA2']);
              final teamB = _formatTeam(match['playerB1'], match['playerB2']);
              final date = _formatShortDate(match['createdAt']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: won ? const Color(0xFF81C784) : const Color(0xFFE57373),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        won ? 'W' : 'L',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            date,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8A8A8A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$teamA : $teamB',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF5A4038),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$teamAScore : $teamBScore',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  String _formatTeam(dynamic p1, dynamic p2) {
    final a = p1?.toString() ?? '-';
    final b = p2?.toString() ?? '-';
    return '$a·$b';
  }

  String _formatShortDate(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }

  void _showRecentMatchesDialog(List<dynamic> recentMatches) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('최근 전적'),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: ListView.separated(
            itemCount: recentMatches.length,
            separatorBuilder: (_, __) => const Divider(height: 16),
            itemBuilder: (_, index) {
              final match = recentMatches[index];
              final won = match['won'] == true;
              final teamAScore = match['teamAScore'] ?? 0;
              final teamBScore = match['teamBScore'] ?? 0;
              final teamA = _formatTeam(match['playerA1'], match['playerA2']);
              final teamB = _formatTeam(match['playerB1'], match['playerB2']);
              final date = _formatShortDate(match['createdAt']);
              return Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: won ? const Color(0xFF81C784) : const Color(0xFFE57373),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      won ? 'W' : 'L',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          date,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8A8A8A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$teamA : $teamB',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF5A4038),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$teamAScore : $teamBScore',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4038),
          ),
        ),
      ],
    );
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
              icon: Icons.person_search,
              label: '프로필 보기',
              color: const Color(0xFF64B5F6),
              onTap: () {
                Navigator.pop(context);
                _showPlayerProfileDialog(nickname, game);
              },
            ),
            const SizedBox(height: 10),
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
    final reasons = [
      '욕설/비방',
      '도배/스팸',
      '부적절한 닉네임',
      '게임 방해',
      '기타',
    ];
    String? selectedReason;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.flag, color: Color(0xFFE57373)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$nickname 신고',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF0C7C7)),
                  ),
                  child: const Text(
                    '신고는 운영팀이 확인합니다.\n허위 신고는 제재될 수 있어요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9A4A4A),
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '사유 선택',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: reasons.map((r) {
                    final isSelected = selectedReason == r;
                    return InkWell(
                      onTap: () => setState(() => selectedReason = r),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFDDECF7)
                              : const Color(0xFFF6F2F0),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF9EC5E6)
                                : const Color(0xFFE2D8D4),
                          ),
                        ),
                        child: Text(
                          r,
                          style: TextStyle(
                            fontSize: 12,
                            color: isSelected
                                ? const Color(0xFF3E6D8E)
                                : const Color(0xFF6A5A52),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: '상세 사유를 입력해주세요 (선택)',
                    filled: true,
                    fillColor: const Color(0xFFF7F2F0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0D6D1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFB9A8A1)),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: selectedReason == null
                    ? null
                    : () {
                        final detail = reasonController.text.trim();
                        final reason = detail.isEmpty
                            ? selectedReason!
                            : '${selectedReason!} / $detail';
                        Navigator.pop(ctx);
                        game.reportResultSuccess = null;
                        game.reportResultMessage = null;
                        game.reportUserAction(nickname, reason);
                        void listener() {
                          if (game.reportResultMessage != null) {
                            game.removeListener(listener);
                            if (mounted) {
                              final success = game.reportResultSuccess == true;
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                SnackBar(
                                  content: Text(game.reportResultMessage!),
                                  backgroundColor:
                                      success ? null : const Color(0xFFE57373),
                                ),
                              );
                            }
                            game.reportResultSuccess = null;
                            game.reportResultMessage = null;
                          }
                        }
                        game.addListener(listener);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE57373),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('신고하기'),
              ),
            ],
          );
        },
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
              game.gameState = null;
              game.desertedPlayerName = null;
              game.desertedReason = null;
              game.dragonGivenMessage = null;
              game.currentRoomId = '';
              game.currentRoomName = '';
              game.roomPlayers = [null, null, null, null];
              game.isHost = false;
              game.chatMessages = [];
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

  Widget _buildDragonGivenBanner(String message) {
    return Positioned(
      bottom: 240,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF66BB6A)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🐉', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              message,
              style: const TextStyle(
                color: Color(0xFF2E7D32),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeoutBanner(String playerName) {
    return Positioned(
      bottom: 240,
      left: 20,
      right: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB74D)),
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
            const Icon(Icons.timer_off, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$playerName 시간 초과!',
                style: const TextStyle(
                  color: Color(0xFFE65100),
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

  Widget _buildDesertionBanner(String playerName, String reason) {
    return Positioned(
      bottom: 240,
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
            const Icon(Icons.person_off, color: Color(0xFFCC4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                reason == 'timeout'
                    ? '$playerName 탈주! (시간 초과 3회)'
                    : '$playerName 님이 게임을 떠났습니다',
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

  Widget _buildCardViewersChips(GameService game) {
    return Positioned(
      top: 40,
      right: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: game.cardViewers.map((viewer) {
          final nickname = viewer['nickname'] ?? '';
          final spectatorId = viewer['id'] ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility, size: 14, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(
                    nickname,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => game.revokeCardView(spectatorId),
                    child: const Icon(Icons.close, size: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPartnerArea(GameStateData state, GameService game) {
    final partner = _firstWhereOrNull(
      state.players,
      (p) => p.position == 'partner',
    );
    final isPartnerTurn = partner?.id == state.currentPlayer;

    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          GestureDetector(
            onTap: partner != null ? () => _showPlayerProfileDialog(partner.name, game) : null,
            child: _buildTurnName(
              name: partner?.name ?? '파트너',
              isTurn: isPartnerTurn,
              badge: _tichuBadgeForPlayer(partner),
              connected: partner?.connected ?? true,
            ),
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
              GestureDetector(
                onTap: left != null ? () => _showPlayerProfileDialog(left.name, game) : null,
                child: _buildTurnName(
                  name: left?.name ?? '좌측',
                  isTurn: isLeftTurn,
                  fontSize: 12,
                  badge: _tichuBadgeForPlayer(left),
                  connected: left?.connected ?? true,
                ),
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
              GestureDetector(
                onTap: right != null ? () => _showPlayerProfileDialog(right.name, game) : null,
                child: _buildTurnName(
                  name: right?.name ?? '우측',
                  isTurn: isRightTurn,
                  fontSize: 12,
                  badge: _tichuBadgeForPlayer(right),
                  connected: right?.connected ?? true,
                ),
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  ),
                ],
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
          // My name (tappable for profile) + status
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _showPlayerProfileDialog(game.playerName, game),
                child: Text(
                  game.playerName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64B5F6),
                    decoration: TextDecoration.underline,
                    decorationColor: Color(0xFF64B5F6),
                  ),
                ),
              ),
              if (isMyTurn) ...[
                const SizedBox(width: 8),
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
              ],
              if (_tichuBadgeForSelf(state) != null) ...[
                const SizedBox(width: 8),
                _tichuBadgeForSelf(state)!,
              ],
            ],
          ),
          const SizedBox(height: 8),

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
    return Positioned(
      bottom: 280,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
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
      ),
    );
  }

  Widget _buildExchangeDialog(GameStateData state, GameService game) {
    final left = _firstWhereOrNull(state.players, (p) => p.position == 'left');
    final partner = _firstWhereOrNull(state.players, (p) => p.position == 'partner');
    final right = _firstWhereOrNull(state.players, (p) => p.position == 'right');

    final selectedCard = _selectedCards.isNotEmpty ? _selectedCards.first : null;
    final assignedCount = _exchangeAssignments.length;

    return Positioned(
      bottom: 280,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  selectedCard != null ? '카드를 줄 상대 선택' : '교환할 카드 선택 ($assignedCount/3)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                if (_exchangeAssignments.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  SizedBox(
                    height: 28,
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _exchangeAssignments.clear();
                          _selectedCards.clear();
                        });
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('초기화', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                SizedBox(
                  height: 28,
                  child: ElevatedButton(
                    onPressed: assignedCount == 3
                        ? () {
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
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('교환 완료', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
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
          ],
        ),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
              const SizedBox(width: 4),
              const Icon(Icons.check_circle, size: 14, color: Color(0xFF3A5A40)),
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

    if (isGameEnd && game.isRankedRoom) {
      final profile = game.profileData;
      if (profile == null || profile['nickname'] != game.playerName) {
        game.requestProfile(game.playerName);
      }
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
          if (isGameEnd && game.isRankedRoom) ...[
            const SizedBox(height: 14),
            _buildRankedResult(game),
          ],
          if (!isGameEnd) ...[
            const SizedBox(height: 12),
            const Text(
              '3초 후 자동 진행...',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
            ),
          ],
          if (isGameEnd) ...[
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                game.leaveRoom();
                game.gameState = null;
                game.desertedPlayerName = null;
                game.desertedReason = null;
                game.dragonGivenMessage = null;
                game.currentRoomId = '';
                game.currentRoomName = '';
                game.roomPlayers = [null, null, null, null];
                game.isHost = false;
                game.chatMessages = [];
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const LobbyScreen()),
                );
              },
              child: const Text('로비로 돌아가기'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRankedResult(GameService game) {
    final profile = game.profileData;
    if (profile == null || profile['nickname'] != game.playerName) {
      return const SizedBox(
        height: 40,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final data = profile['profile'] as Map<String, dynamic>?;
    if (data == null) {
      return const SizedBox.shrink();
    }
    final seasonRating = data['seasonRating'] ?? 1000;
    final tier = _rankTier(seasonRating);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F3FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4DFF2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _rankBadge(tier),
          const SizedBox(width: 10),
          Text(
            '랭크전 점수 $seasonRating',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4A4080),
            ),
          ),
        ],
      ),
    );
  }

  _RankTier _rankTier(int rating) {
    if (rating >= 1500) return _RankTier.diamond;
    if (rating >= 1300) return _RankTier.gold;
    if (rating >= 1100) return _RankTier.silver;
    return _RankTier.bronze;
  }

  Widget _rankBadge(_RankTier tier) {
    switch (tier) {
      case _RankTier.diamond:
        return _rankPill('다이아', const Color(0xFF69B7FF), Icons.diamond_outlined);
      case _RankTier.gold:
        return _rankPill('골드', const Color(0xFFFFD54F), Icons.emoji_events);
      case _RankTier.silver:
        return _rankPill('실버', const Color(0xFFB0BEC5), Icons.emoji_events);
      case _RankTier.bronze:
        return _rankPill('브론즈', const Color(0xFFC58B6B), Icons.emoji_events);
    }
  }

  Widget _rankPill(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
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
    // Wait until exchange is fully performed (phase moves past card_exchange)
    if (state.phase == 'card_exchange') return;
    if (_exchangeGiven.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _exchangeSummaryShown) return;
      _exchangeSummaryShown = true;
      final leftName = _nameForPosition(state, 'left');
      final partnerName = _nameForPosition(state, 'partner');
      final rightName = _nameForPosition(state, 'right');

      final givenLeft = _exchangeGiven['left'];
      final givenPartner = _exchangeGiven['partner'];
      final givenRight = _exchangeGiven['right'];

      // Use server-provided receivedFrom data
      final receivedLeft = state.receivedFrom?['left'];
      final receivedPartner = state.receivedFrom?['partner'];
      final receivedRight = state.receivedFrom?['right'];

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
                '받은 카드',
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

enum _RankTier { bronze, silver, gold, diamond }

class _ExchangeSummaryItem {
  final String name;
  final String? cardId;
  const _ExchangeSummaryItem(this.name, this.cardId);
}
