import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../services/network_service.dart';
import '../models/mighty_game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/level_badge.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n_helpers.dart';

class MightyGameScreen extends StatefulWidget {
  const MightyGameScreen({super.key});

  @override
  State<MightyGameScreen> createState() => _MightyGameScreenState();
}

class _MightyGameScreenState extends State<MightyGameScreen> {
  // Bidding state
  int _bidPoints = 13;
  String _bidSuit = 'spade';

  // Kitty exchange state
  final Set<String> _discardSelection = {};
  String _friendCardSelection = '';
  String _friendMode = ''; // 'no_friend', 'first_trick', 'card'
  String _friendSuit = 'spade';
  String _friendRank = 'A';
  String? _selectedTrumpSuit; // null = no change
  String?
  _lastKnownTrumpSuit; // tracks the last trumpSuit we rendered for; used to resync _selectedTrumpSuit when the server confirms a change
  String?
  _lastKittyMightyCard; // last mighty card seen while in kitty_exchange — when trump change makes mighty change AND declarer no longer holds it, default the friend pick to mighty-friend

  // Kitty-phase contract-change banner: auto-dismissing overlay that
  // highlights trump/bid changes so non-declarers notice them.
  String? _kittyContractTrump;
  int? _kittyContractBid;
  _ContractChangeInfo? _contractChangeBanner;
  Timer? _contractChangeTimer;

  // Play state
  String? _selectedCard;
  String? _jokerSuitChoice;
  bool _jokerCallChoice = true; // default Yes for joker call

  // Timer
  Timer? _countdownTimer;
  int _remainingSeconds = 0;

  // Game end
  Timer? _gameEndCountdownTimer;
  int _gameEndCountdown = 3;
  bool _gameEndCountdownActive = false;

  // Phase tracking for clearing stale state
  String _lastPhase = '';

  // Track whether the local player was excluded last frame so we can clear
  // pseudo-spectator state (approved peeks, pending requests, viewing target)
  // when they rejoin the table next round.
  bool _wasSelfExcluded = false;

  // Track the number of completed tricks so we can clear a pre-selection when
  // a new trick starts (lead suit changes).
  int _lastTrickCount = -1;

  // Deal-miss reveal: user can dismiss; keyed by "round-playerId" so a new event re-shows
  String? _dismissedDealMissKey;

  // Kill reveal: same pattern — keyed by "round-targetCardId" so it only shows once
  String? _dismissedKillKey;
  // Auto-dismiss the kill reveal after a few seconds if the user doesn't tap.
  Timer? _killAutoDismissTimer;
  String? _killAutoDismissKey;
  // Setting-reveal dismissal (same pattern as deal-miss/kill).
  String? _dismissedSettingKey;
  String? _selectedKillCard;
  // Kill target picker: currently browsed suit panel (null = joker tab).
  String _killSuitTab = 'spade';

  // Spectator card view
  Timer? _cardViewRequestTimer;
  String? _viewingPlayerId;

  // Chat
  bool _chatOpen = false;
  bool _soundPanelOpen = false;
  bool _viewersOpen = false;
  bool _moreOpen = false;
  int _readChatCount = 0;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  int _lastChatMessageCount = 0;

  // Network
  bool _wasDisconnected = false;
  GameService? _gameService;
  NetworkService? _networkService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gameService = context.read<GameService>();
      _networkService = context.read<NetworkService>();
      _networkService!.addListener(_onNetworkChanged);
      _readChatCount = _gameService!.chatMessages.length;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  void _onNetworkChanged() {
    if (!mounted) return;
    final network = _networkService;
    if (network == null) return;
    if (!network.isConnected) {
      _wasDisconnected = true;
    } else if (_wasDisconnected && network.isConnected) {
      _wasDisconnected = false;
      context.read<GameService>().checkRoom();
    }
  }

  @override
  void dispose() {
    _networkService?.removeListener(_onNetworkChanged);
    _chatController.dispose();
    _chatScrollController.dispose();
    _countdownTimer?.cancel();
    _gameEndCountdownTimer?.cancel();
    _cardViewRequestTimer?.cancel();
    _contractChangeTimer?.cancel();
    _killAutoDismissTimer?.cancel();
    super.dispose();
  }

  void _updateCountdown() {
    if (!mounted) return;
    final state = _gameService?.mightyGameState;
    if (state == null || state.turnDeadline == null) {
      if (_remainingSeconds != 0) setState(() => _remainingSeconds = 0);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((state.turnDeadline! - now) / 1000).ceil().clamp(0, 999);
    if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
    }
  }

  void _syncGameEndCountdown(String phase) {
    if (phase == 'game_end') {
      if (_gameEndCountdownActive) return;
      _gameEndCountdownActive = true;
      _gameEndCountdown = 3;
      _gameEndCountdownTimer?.cancel();
      _gameEndCountdownTimer = Timer.periodic(const Duration(seconds: 1), (
        timer,
      ) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_gameEndCountdown <= 1) {
          timer.cancel();
          _gameEndCountdownActive = false;
          setState(() => _gameEndCountdown = 0);
          _gameService?.returnToRoom();
        } else {
          setState(() => _gameEndCountdown--);
        }
      });
    } else {
      _gameEndCountdownActive = false;
      _gameEndCountdownTimer?.cancel();
    }
  }

  String _displayCardId(String id) {
    if (id == 'mighty_joker') return 'joker';
    return id.replaceFirst('mighty_', '');
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = context.watch<GameService>().themeGradient;

    return ConnectionOverlay(
      child: PopScope(
        canPop: false,
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: themeColors,
              ),
            ),
            child: Stack(
              children: [
                SafeArea(child: _buildMainContent()),
                // Edge-to-edge dim + result UI for round_end / game_end so the
                // dim layer extends into status bar / nav bar regions instead
                // of being clipped by SafeArea.
                Consumer<GameService>(
                  builder: (context, game, _) =>
                      _buildEndPhaseOverlay(context, game),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return Consumer<GameService>(
                builder: (context, game, _) {
                  final state = game.mightyGameState;
                  if (state == null) {
                    if (game.isSpectator &&
                        game.hasRoom &&
                        !game.hasActiveGame) {
                      return _buildSpectatorWaiting(game);
                    }
                    return const Center(child: CircularProgressIndicator());
                  }
                  // Clear stale pseudo-spectator state when the local player
                  // stops being killed (i.e. next round started and they
                  // rejoined the table). Server-side permissions are already
                  // wiped by pruneCardViewPermissions.
                  {
                    final myId = game.playerId;
                    final isSelfExcluded =
                        myId.isNotEmpty && state.excludedPlayers.contains(myId);
                    if (_wasSelfExcluded && !isSelfExcluded) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          game.approvedCardViews.clear();
                          game.pendingCardViewRequests.clear();
                          _viewingPlayerId = null;
                          _cardViewRequestTimer?.cancel();
                        });
                      });
                    }
                    if (_wasSelfExcluded != isSelfExcluded) {
                      _wasSelfExcluded = isSelfExcluded;
                    }
                  }
                  // Clear any pre-selection at trick boundaries: the lead suit
                  // changes every trick, so whatever the user queued up before
                  // may no longer be legal on the new trick.
                  if (_lastTrickCount != state.tricks.length) {
                    if (_lastTrickCount != -1 && _selectedCard != null) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() => _selectedCard = null);
                      });
                    }
                    _lastTrickCount = state.tricks.length;
                  }
                  // Trump change during kitty_exchange may change which card is
                  // mighty. If the new mighty isn't in declarer's hand, reset
                  // the friend pick to mighty-friend so the host doesn't have
                  // to re-pick manually.
                  if (state.phase == 'kitty_exchange') {
                    final currentMighty = state.mightyCard;
                    if (_lastKittyMightyCard != null &&
                        _lastKittyMightyCard != currentMighty &&
                        currentMighty != null &&
                        !state.myCards.contains(currentMighty)) {
                      final parts = currentMighty
                          .replaceFirst('mighty_', '')
                          .split('_');
                      final newSuit = parts.isNotEmpty ? parts[0] : 'spade';
                      final newRank = parts.length > 1 ? parts[1] : 'A';
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() {
                          _friendMode = 'card';
                          _friendSuit = newSuit;
                          _friendRank = newRank;
                          _friendCardSelection = currentMighty;
                        });
                      });
                    }
                    _lastKittyMightyCard = currentMighty;
                  } else if (_lastKittyMightyCard != null) {
                    _lastKittyMightyCard = null;
                  }
                  // Clear stale state on phase change
                  if (_lastPhase != state.phase) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _syncGameEndCountdown(state.phase);
                      setState(() {
                        _lastPhase = state.phase;
                        _selectedCard = null;
                        _jokerSuitChoice = null;
                        _jokerCallChoice = true;
                        if (state.phase == 'bidding') {
                          _bidPoints = state.mode == '6p' ? 14 : 13;
                          _bidSuit = 'spade';
                          _discardSelection.clear();
                          _friendCardSelection = '';
                          _friendMode = '';
                          _friendSuit = 'spade';
                          _friendRank = 'A';
                          _selectedTrumpSuit = null;
                          _lastKnownTrumpSuit = null;
                        }
                        if (state.phase == 'kitty_exchange') {
                          _discardSelection.clear();
                          _selectedTrumpSuit = null;
                          _lastKnownTrumpSuit = null;
                          // Smart default, in priority order:
                          //   1. Hand holds BOTH mighty AND joker → first-trick
                          //      friend (strong hand, the first-trick winner
                          //      makes a great partner).
                          //   2. Missing mighty → call mighty as friend card.
                          //   3. Suited bid, missing trump-A → call trump A.
                          //   4. Missing joker → joker-call friend.
                          //   5. Otherwise → leave unset so host picks
                          //      explicitly (confirm button stays disabled).
                          final myCards = state.myCards;
                          final mightyCard = state.mightyCard;
                          final trump = state.trumpSuit ?? 'spade';
                          final isNT = trump == 'no_trump';
                          final hasMighty =
                              mightyCard != null &&
                              myCards.contains(mightyCard);
                          final hasJoker = myCards.contains('mighty_joker');
                          final trumpAce = isNT ? null : 'mighty_${trump}_A';
                          final hasTrumpAce =
                              trumpAce != null && myCards.contains(trumpAce);

                          if (hasMighty && hasJoker) {
                            _friendMode = 'first_trick';
                            _friendCardSelection = 'first_trick';
                          } else if (mightyCard != null && !hasMighty) {
                            final parts = mightyCard
                                .replaceFirst('mighty_', '')
                                .split('_');
                            _friendMode = 'card';
                            _friendSuit = parts.isNotEmpty ? parts[0] : 'spade';
                            _friendRank = parts.length > 1 ? parts[1] : 'A';
                            _friendCardSelection =
                                'mighty_${_friendSuit}_$_friendRank';
                          } else if (trumpAce != null && !hasTrumpAce) {
                            _friendMode = 'card';
                            _friendSuit = trump;
                            _friendRank = 'A';
                            _friendCardSelection = trumpAce;
                          } else if (!hasJoker) {
                            _friendMode = 'joker';
                            _friendCardSelection = 'mighty_joker';
                          } else {
                            _friendMode = '';
                            _friendCardSelection = '';
                          }
                        }
                      });
                    });
                  }

                  // Clear selected card if it's no longer in hand
                  if (_selectedCard != null &&
                      !state.myCards.contains(_selectedCard)) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _selectedCard = null);
                    });
                  }

                  // Kill-reveal auto-dismiss: when a fresh (non-dismissed) kill
                  // event appears, schedule a 4-second auto-close so the
                  // overlay doesn't block the game indefinitely if nobody
                  // taps it. Keyed by round+targetCard so replaying the same
                  // event in a later round re-arms the timer.
                  if (state.lastKillEvent != null) {
                    final killKey =
                        '${state.round}-${state.lastKillEvent!.targetCardId}';
                    final isActive = _dismissedKillKey != killKey;
                    if (isActive && _killAutoDismissKey != killKey) {
                      _killAutoDismissKey = killKey;
                      _killAutoDismissTimer?.cancel();
                      _killAutoDismissTimer = Timer(
                        const Duration(seconds: 4),
                        () {
                          if (!mounted) return;
                          setState(() => _dismissedKillKey = killKey);
                        },
                      );
                    } else if (!isActive && _killAutoDismissKey == killKey) {
                      _killAutoDismissTimer?.cancel();
                    }
                  }

                  // Kitty-phase contract-change detection: flash a banner when
                  // the declarer changes trump or raises the bid so the other
                  // players notice the contract shift.
                  if (state.phase == 'kitty_exchange' &&
                      state.declarer != null) {
                    final currTrump = state.trumpSuit;
                    final currBid = (state.currentBid['points'] as num?)
                        ?.toInt();
                    if (_kittyContractTrump != null &&
                        _kittyContractBid != null) {
                      final trumpChanged =
                          currTrump != null && currTrump != _kittyContractTrump;
                      final bidRaised =
                          currBid != null && currBid > _kittyContractBid!;
                      if (trumpChanged || bidRaised) {
                        final info = _ContractChangeInfo(
                          oldTrump: trumpChanged ? _kittyContractTrump : null,
                          newTrump: trumpChanged ? currTrump : null,
                          oldBid: bidRaised ? _kittyContractBid : null,
                          newBid: bidRaised ? currBid : null,
                        );
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          setState(() => _contractChangeBanner = info);
                          _contractChangeTimer?.cancel();
                          _contractChangeTimer = Timer(
                            const Duration(milliseconds: 2600),
                            () {
                              if (!mounted) return;
                              setState(() => _contractChangeBanner = null);
                            },
                          );
                        });
                      }
                    }
                    _kittyContractTrump = currTrump;
                    _kittyContractBid = currBid;
                  } else {
                    if (_kittyContractTrump != null ||
                        _kittyContractBid != null) {
                      _kittyContractTrump = null;
                      _kittyContractBid = null;
                    }
                  }

                  return Stack(
                    children: [
                      Column(
                        children: [
                          _buildTopBar(state, game),
                          if (state.phase == 'playing' ||
                              state.phase == 'trick_end' ||
                              state.phase == 'round_end')
                            _buildOppositionPointBar(state),
                          Expanded(child: _buildActiveBoardStage(state, game)),
                        ],
                      ),
                      if (_moreOpen) _buildMoreMenu(game),
                      if (_viewersOpen) _buildViewersPanel(game),
                      if (_soundPanelOpen) _buildSoundPanel(game),
                      if (_chatOpen) _buildChatPanel(game),
                      if (game.hasIncomingCardViewRequests)
                        _buildCardViewRequestPopup(game),
                      if (game.timeoutPlayerName != null)
                        _buildTimeoutBanner(game.timeoutPlayerName!),
                      if (game.errorMessage != null)
                        _buildErrorBanner(game.errorMessage!),
                      if (state.lastDealMissEvent != null &&
                          _dismissedDealMissKey !=
                              '${state.lastDealMissEvent!.round}-${state.lastDealMissEvent!.playerId}')
                        _buildDealMissRevealOverlay(state.lastDealMissEvent!),
                      if (state.lastKillEvent != null &&
                          _dismissedKillKey !=
                              '${state.round}-${state.lastKillEvent!.targetCardId}')
                        _buildKillRevealOverlay(state, state.lastKillEvent!),
                      if (state.lastSettingEvent != null &&
                          _dismissedSettingKey !=
                              '${state.lastSettingEvent!.round}-${state.lastSettingEvent!.playerId}')
                        _buildSettingRevealOverlay(state.lastSettingEvent!),
                      if (_contractChangeBanner != null)
                        _buildContractChangeBanner(_contractChangeBanner!),
                    ],
                  );
                },
              );
  }

  Widget _buildEndPhaseOverlay(BuildContext context, GameService game) {
    final state = game.mightyGameState;
    if (state == null) return const SizedBox.shrink();
    final isRoundEnd = state.phase == 'round_end';
    final isGameEnd = state.phase == 'game_end';
    if (!isRoundEnd && !isGameEnd) return const SizedBox.shrink();
    return Stack(
      children: [
        // Full-bleed dim (extends into status bar / nav bar regions).
        Positioned.fill(
          child: IgnorePointer(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.10)),
          ),
        ),
        // Result UI inside its own SafeArea so the content stays readable.
        SafeArea(
          child: Align(
            alignment: isRoundEnd
                ? Alignment.bottomCenter
                : Alignment.center,
            child: SingleChildScrollView(
              padding: isRoundEnd
                  ? const EdgeInsets.fromLTRB(12, 20, 12, 20)
                  : const EdgeInsets.fromLTRB(12, 20, 12, 24),
              child: isRoundEnd
                  ? _buildRoundEndUI(state)
                  : _buildGameEndUI(state, game),
            ),
          ),
        ),
      ],
    );
  }

  // ── Spectator Waiting Room ──
  Widget _buildSpectatorWaiting(GameService game) {
    final slots = game.roomPlayers;
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.90),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE0D8D4)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => game.leaveRoom(),
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF5A4038)),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.spectatorWatching,
                    style: const TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    game.currentRoomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF5A4038),
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _buildTopActionButton(
                  icon: Icons.chat_bubble_outline,
                  active: _chatOpen,
                  badgeCount: _chatOpen
                      ? 0
                      : (game.chatMessages.length - _readChatCount).clamp(
                          0,
                          99,
                        ),
                  onTap: () {
                    setState(() {
                      _chatOpen = !_chatOpen;
                      if (_chatOpen) _readChatCount = game.chatMessages.length;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Slot grid
          Expanded(
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 760),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFE0D8D4)),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth > 620;
                          return GridView.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: wide ? 2 : 1,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 12,
                                  childAspectRatio: wide ? 2.4 : 4.0,
                                ),
                            itemCount: slots.length,
                            itemBuilder: (context, index) {
                              return _buildWaitingSlot(
                                game,
                                slots[index],
                                index,
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.spectatorWaitingForGame,
                      style: const TextStyle(
                        color: Color(0xFF8A8A8A),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_chatOpen) ...[
            const SizedBox(height: 8),
            SizedBox(height: 200, child: _buildChatPanel(game)),
          ],
        ],
      ),
    );
  }

  Widget _buildWaitingSlot(GameService game, Player? player, int slotIndex) {
    final isBlocked = game.roomBlockedSlots.contains(slotIndex);
    if (isBlocked) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EDED),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD8CFCB)),
        ),
        child: const Row(
          children: [Icon(Icons.block, size: 24, color: Color(0xFFBDB5B0))],
        ),
      );
    }
    if (player == null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => game.switchToPlayer(slotIndex),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F2F0),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD8CFCB)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_add,
                  size: 24,
                  color: Color(0xFF9AA7B0),
                ),
                const SizedBox(width: 10),
                Text(
                  L10n.of(context).spectatorSit,
                  style: const TextStyle(
                    color: Color(0xFF9AA7B0),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final isReady = player.isReady;
    return GestureDetector(
      onTap: () => _showPlayerProfileDialog(
        player.name,
        game,
        isBot: player.id.startsWith('bot_'),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isReady
                    ? const Color(0xFF9ED6A5)
                    : const Color(0xFFE0D8D4),
                width: isReady ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                if (player.level != null)
                  LevelBadge(level: player.level, size: 36)
                else
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.person,
                      color: Color(0xFF2E7D32),
                      size: 20,
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    player.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3E312A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Ready state is conveyed via the background check watermark
                // (see Stack below), so the inline READY chip is removed —
                // keeps the name area from getting squeezed when ready toggles.
              ],
            ),
          ),
          if (isReady)
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
          if (player.isHost)
            const Positioned(
              left: -2,
              top: -6,
              child: Text(
                '👑',
                style: TextStyle(fontSize: 18, height: 1.0),
              ),
            ),
        ],
      ),
    );
  }

  // ── Top Bar (SK-style) ──
  Widget _buildTopBar(MightyGameStateData state, GameService game) {
    final hasCurrentBidder = state.currentBid['bidder'] != null;
    final showContractInfo =
        (state.declarer != null &&
            state.phase != 'bidding' &&
            state.phase != 'dealing') ||
        (state.phase == 'bidding' &&
            (hasCurrentBidder || state.dealMissPool > 0));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFCCCCCC)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.style, size: 14, color: Color(0xFF5A4038)),
                    const SizedBox(width: 5),
                    Text(
                      state.phase == 'round_end'
                          ? L10n.of(
                              context,
                            ).mtRoundOnly(state.round.toString())
                          : L10n.of(context).mtRoundPhase(
                              state.round.toString(),
                              _phaseLabel(state.phase),
                            ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (state.scoreHistory.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildTopActionButton(
                    icon: Icons.history,
                    active: false,
                    onTap: () => _showScoreHistoryDialog(state, game),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildTopActionButton(
                  icon: Icons.chat_bubble_outline,
                  active: _chatOpen,
                  badgeCount: _chatOpen
                      ? 0
                      : (game.chatMessages.length - _readChatCount).clamp(
                          0,
                          99,
                        ),
                  onTap: () {
                    setState(() {
                      _chatOpen = !_chatOpen;
                      if (_chatOpen) {
                        _readChatCount = game.chatMessages.length;
                        _moreOpen = false;
                        _viewersOpen = false;
                        _soundPanelOpen = false;
                        _scrollChatToBottom();
                      }
                    });
                  },
                ),
              ),
              _buildTopActionButton(
                icon: Icons.more_horiz,
                active: _moreOpen,
                onTap: () {
                  setState(() {
                    _moreOpen = !_moreOpen;
                    if (_moreOpen) {
                      _chatOpen = false;
                      _viewersOpen = false;
                      _soundPanelOpen = false;
                    } else {
                      _soundPanelOpen = false;
                    }
                  });
                },
              ),
            ],
          ),
        ),
        if (showContractInfo) _buildContractInfoBar(state, game),
      ],
    );
  }

  Widget _buildSoundPanel(GameService game) {
    final l10n = L10n.of(context);
    final title = game.isSpectator
        ? l10n.spectatorSoundEffects
        : l10n.gameSoundEffects;

    return Positioned(
      top: 120,
      right: 8,
      child: Container(
        width: 190,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
            Slider(
              value: game.sfxVolume,
              onChanged: (value) => game.setSfxVolume(value),
              onChangeEnd: (value) => game.setSfxVolume(value, persist: true),
              min: 0,
              max: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewersPanel(GameService game) {
    return Positioned(
      top: 56,
      right: 8,
      child: Container(
        width: 210,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.visibility,
                  size: 16,
                  color: Color(0xFF5A4038),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    L10n.of(context).gameViewingMyCards,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _viewersOpen = false),
                  child: const Icon(
                    Icons.close,
                    size: 18,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (game.cardViewers.isEmpty)
              Text(
                L10n.of(context).skGameNoViewers,
                style: const TextStyle(fontSize: 12, color: Color(0xFF999999)),
              )
            else
              ...game.cardViewers.map((viewer) {
                final nickname = viewer['nickname'] ?? '';
                final spectatorId = viewer['id'] ?? '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person,
                        size: 16,
                        color: Color(0xFF888888),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          nickname,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => game.revokeCardView(spectatorId),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Color(0xFFE53935),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildMoreMenu(GameService game) {
    final hasViewers = game.cardViewers.isNotEmpty;
    return Positioned(
      top: 56,
      right: 8,
      child: Container(
        width: hasViewers ? 210 : 170,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildTopActionButton(
              icon: Icons.people_alt,
              active: false,
              badgeCount: game.spectators.length,
              onTap: () {
                setState(() {
                  _moreOpen = false;
                  _soundPanelOpen = false;
                });
                _showSpectatorListDialog(game);
              },
            ),
            if (hasViewers)
              _buildTopActionButton(
                icon: Icons.visibility,
                active: _viewersOpen,
                badgeCount: game.cardViewers.length,
                onTap: () {
                  setState(() {
                    _moreOpen = false;
                    _soundPanelOpen = false;
                    _viewersOpen = !_viewersOpen;
                  });
                },
              ),
            _buildTopActionButton(
              icon: game.sfxVolume <= 0.01 ? Icons.volume_off : Icons.volume_up,
              active: _soundPanelOpen,
              onTap: () {
                setState(() {
                  _soundPanelOpen = !_soundPanelOpen;
                  if (_soundPanelOpen) {
                    _viewersOpen = false;
                  }
                });
              },
            ),
            _buildTopActionButton(
              icon: Icons.exit_to_app,
              active: false,
              iconColor: const Color(0xFFE53935),
              onTap: () {
                setState(() {
                  _moreOpen = false;
                  _soundPanelOpen = false;
                });
                _showExitConfirmDialog(game);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContractInfoBar(MightyGameStateData state, GameService game) {
    final isBidding = state.phase == 'bidding';
    final leaderId = isBidding
        ? state.currentBid['bidder'] as String?
        : state.declarer;
    final leaderName = leaderId == null
        ? ''
        : (state.players
                  .where((p) => p.id == leaderId)
                  .map((p) => p.name)
                  .firstOrNull ??
              '');
    final bidPoints = state.currentBid['points'];
    final bidSuit = state.currentBid['suit'];
    final hasBid = bidPoints != null && (bidPoints is num) && bidPoints > 0;

    // Info bar shows WHICH CARD is the friend, not who the partner is.
    // The reveal (partner name) is already visible on the scoreboard via
    // the 'Friend' role badge, so we don't need to duplicate it here.
    String? friendCardSuit;
    String? friendCardRank;
    String friendSuffixText = '';
    String? friendSpecialText;
    if (!isBidding) {
      final friendCard = state.friendCard;
      if (friendCard == null) {
        friendSpecialText = L10n.of(context).mtSolo;
      } else if (friendCard == 'mighty_joker') {
        friendSpecialText = L10n.of(context).mtFriendCardJoker;
        friendSuffixText = ' ${L10n.of(context).mtFriend}';
      } else if (friendCard == 'no_friend') {
        friendSpecialText = L10n.of(context).mtFriendCardSolo;
      } else if (friendCard == 'first_trick') {
        friendSpecialText = L10n.of(context).mtFriendCard1st;
        friendSuffixText = ' ${L10n.of(context).mtFriend}';
      } else {
        final parts = friendCard.replaceFirst('mighty_', '').split('_');
        if (parts.length == 2) {
          friendCardSuit = parts[0];
          friendCardRank = parts[1];
          friendSuffixText = ' ${L10n.of(context).mtFriend}';
        }
      }
    }
    final hasFriendInfo =
        friendCardSuit != null || friendSpecialText != null;
    // Plain-text version used only for width estimation below.
    final friendEstimateText = friendCardSuit != null
        ? '$friendCardRank$friendSuffixText'
        : '${friendSpecialText ?? ''}$friendSuffixText';

    final showTrumpCounter =
        state.remainingTrumps != null && game.hasMightyTrumpCounter;

    // Estimate the center content's width using rough per-character widths.
    // CJK glyphs are roughly em-wide; ASCII a bit narrower. Used only to decide
    // whether the right-side deal-miss chip would overlap the centered info,
    // not for layout — Stack handles the actual positioning.
    double estimateTextWidth(String text, double charWidth) =>
        text.runes.length * charWidth;
    double centerEstimate = 0;
    if (leaderName.isNotEmpty) {
      centerEstimate += estimateTextWidth(leaderName, 11) + 6;
    }
    if (hasBid) {
      // SuitIcon(11) + gap(3) + "{points}공약" (Korean) ~ 4 glyphs after points
      final bidPointsText =
          L10n.of(context).mtContractWithPoints(bidPoints.toInt());
      centerEstimate +=
          14 + estimateTextWidth(bidPointsText, 12) + 12; // padding
    }
    if (!isBidding && hasFriendInfo) {
      centerEstimate +=
          estimateTextWidth(friendEstimateText, 10) +
          (friendCardSuit != null ? 12 : 0) + // SuitIcon
          18; // separator + spacing
    }

    final dealMissFullWidth = state.dealMissPool > 0
        ? estimateTextWidth(
                L10n.of(
                  context,
                ).mtDealMissPool(state.dealMissPool.toString()),
                10,
              ) +
              16
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Half-center span occupies width/2 ± centerEstimate/2.
          final centerRight = (width + centerEstimate) / 2;
          final dealMissLeftIfFull = width - dealMissFullWidth;
          final useCompactDealMiss =
              state.dealMissPool > 0 &&
              centerRight > dealMissLeftIfFull - 6;

          final centerContent = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leaderName.isNotEmpty)
                Text(
                  leaderName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4038),
                  ),
                ),
              if (leaderName.isNotEmpty && hasBid) const SizedBox(width: 6),
              if (hasBid)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _bidAccentColor(bidSuit?.toString()),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SuitIcon(
                        suit: bidSuit?.toString() ?? '',
                        size: 11,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        L10n.of(
                          context,
                        ).mtContractWithPoints(bidPoints.toInt()),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isBidding && hasFriendInfo) ...[
                const SizedBox(width: 6),
                const Text(
                  '/',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8A7A72)),
                ),
                const SizedBox(width: 6),
                if (friendCardSuit != null) ...[
                  SuitIcon(
                    suit: friendCardSuit,
                    size: 10,
                    color: _bidAccentColor(friendCardSuit),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$friendCardRank$friendSuffixText',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _bidAccentColor(friendCardSuit),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else
                  Text(
                    '${friendSpecialText ?? ''}$friendSuffixText',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF8A7A72),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ],
          );

          final dealMissChip = state.dealMissPool > 0
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFFAB91)),
                  ),
                  child: Text(
                    useCompactDealMiss
                        ? state.dealMissPool.toString()
                        : L10n.of(
                            context,
                          ).mtDealMissPool(state.dealMissPool.toString()),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Color(0xFFD84315),
                    ),
                  ),
                )
              : null;

          return Stack(
            alignment: Alignment.center,
            children: [
              // Center content sits at the true row center regardless of the
              // side chips' widths.
              centerContent,
              if (showTrumpCounter)
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildTrumpCounterLabel(state),
                ),
              if (dealMissChip != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: dealMissChip,
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTrumpCounterLabel(MightyGameStateData state) {
    final trumps = state.remainingTrumps!;
    final count = (trumps['count'] as num?)?.toInt() ?? 0;
    final suit = trumps['suit']?.toString() ?? '';
    final isZero = count == 0;
    final tone = isZero ? const Color(0xFFE53935) : _bidAccentColor(suit);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SuitIcon(suit: suit, size: 12, color: tone),
        const SizedBox(width: 2),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: tone,
          ),
        ),
      ],
    );
  }

  Widget _buildTopActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool active,
    int badgeCount = 0,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF5A4038).withValues(alpha: 0.92)
                  : Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 19,
              color: active
                  ? Colors.white
                  : (iconColor ?? const Color(0xFF5A4038)),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.jumpTo(
          _chatScrollController.position.maxScrollExtent,
        );
      }
    });
  }

  void _sendChatMessage(GameService game) {
    final message = _chatController.text.trim();
    if (message.isEmpty) return;
    game.sendChatMessage(message);
    _chatController.clear();
    _scrollChatToBottom();
  }

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      _readChatCount = game.chatMessages.length;
      _scrollChatToBottom();
    }

    final media = MediaQuery.of(context);
    final keyboardHeight = media.viewInsets.bottom;
    final topInset = media.padding.top;
    final availableWidth = (media.size.width - 16).clamp(220.0, 320.0);
    final topOffset = topInset + 42;
    final bottomOffset = 8 + keyboardHeight;
    final maxHeight = media.size.height - topOffset - bottomOffset;
    final panelHeight = maxHeight.clamp(160.0, 350.0);

    return Positioned(
      right: 8,
      top: topOffset,
      width: availableWidth,
      height: panelHeight,
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF1565C0),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    L10n.of(context).mtChat,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => setState(() => _chatOpen = false),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _chatScrollController,
                padding: const EdgeInsets.all(8),
                itemCount: game.chatMessages.length,
                itemBuilder: (context, index) {
                  final msg = game.chatMessages[index];
                  final sender = msg['sender'] as String? ?? '';
                  String message = msg['message'] as String? ?? '';
                  if (message == 'chat_banned') {
                    final mins = msg['remainingMinutes'] as int? ?? 0;
                    message = localizeChatBanned(mins, L10n.of(context));
                  }
                  final isMe = sender == game.playerName;
                  final isBlocked = sender.isNotEmpty && game.isBlocked(sender);
                  if (isBlocked) return const SizedBox.shrink();
                  return _buildChatBubble(sender, message, isMe);
                },
              ),
            ),
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
                      decoration: InputDecoration(
                        hintText: L10n.of(context).mtTypeMessage,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) => _sendChatMessage(game),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sendChatMessage(game),
                    icon: const Icon(Icons.send, color: Color(0xFF1565C0)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBubble(String sender, String message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe && sender.isNotEmpty) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: const Color(0xFFE0E0E0),
              child: Text(
                sender[0],
                style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMe && sender.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      sender,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A8A8A),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFF1565C0)
                        : const Color(0xFFF0F0F0),
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
    );
  }

  void _showExitConfirmDialog(GameService game) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(L10n.of(context).mtLeaveGame),
        content: Text(L10n.of(context).mtLeaveConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).mtCancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              game.leaveRoom();
            },
            child: Text(
              L10n.of(context).mtLeave,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // Build the compact pass / bid chip shown on a scoreboard tile during the
  // bidding phase. p.bid is either the string 'pass' or a Map {points, suit}.
  Widget? _bidScoreboardBadge(dynamic bid) {
    if (bid == 'pass') {
      return const Text(
        'PASS',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: Color(0xFF9E9E9E),
          letterSpacing: 0.5,
        ),
      );
    }
    if (bid is Map) {
      final points = bid['points'];
      final suit = bid['suit']?.toString() ?? '';
      final accent = _bidAccentColor(suit);
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SuitIcon(suit: suit, size: 9, color: accent),
          const SizedBox(width: 1),
          Text(
            '$points',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      );
    }
    return null;
  }

  Widget _buildTableBoard(MightyGameStateData state, GameService game) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final myId = game.playerId;
    final isSelfExcluded =
        myId.isNotEmpty && state.excludedPlayers.contains(myId);
    final showAllSeats = game.isSpectator;
    final canRequestCardView = game.isSpectator || isSelfExcluded;
    final isBidding = state.phase == 'bidding';
    final isKillSelect = state.phase == 'kill_select';
    final visiblePlayers = showAllSeats
        ? state.players
        : state.players.where((p) => p.position != 'self').toList();
    final activeTrick = state.phase == 'trick_end'
        ? state.lastTrickCards
        : state.currentTrick;
    final winnerId = state.phase == 'trick_end' ? state.lastTrickWinner : null;
    final selfPlay = showAllSeats
        ? null
        : activeTrick.cast<MightyTrickPlay?>().firstWhere(
            (play) => play?.playerId == myId,
            orElse: () => null,
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          final centerX = width / 2;
          const seatWidth = 106.0;
          const seatHeight = 78.0;
          const playedCardWidth = 72 * 0.7;
          const playedCardHeight = 72.0;
          final spectatorBoardDrop = _mightySmallDeviceBoardDrop(
            width: width,
            playerCount: state.players.length,
            spectatorMode: true,
            isLandscape: isLandscape,
          );
          final playerBoardDrop = _mightySmallDeviceBoardDrop(
            width: width,
            playerCount: visiblePlayers.length,
            spectatorMode: false,
            isLandscape: isLandscape,
          );

          if (showAllSeats) {
            final playerCount = state.players.length;
            final centerY =
                (isLandscape ? height * 0.39 : height * 0.41) +
                spectatorBoardDrop;
            final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 10);
            final seatRadiusX = math.min(
              width * _mightySeatRadiusXFactor(playerCount),
              math.min(
                _mightySeatRadiusXCap(width, playerCount, spectator: true),
                maxSeatRadiusX,
              ),
            );
            final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 6);
            final seatRadiusY = math.min(
              height * (isLandscape ? 0.34 : 0.35),
              math.min(
                _mightySeatRadiusYCap(height, spectator: true),
                maxSeatRadiusY,
              ),
            );

            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: Alignment(
                      0,
                      isBidding || isKillSelect
                          ? 0.10
                          : (isLandscape ? 0.36 : 0.46),
                    ),
                    child: isBidding || isKillSelect
                        ? const SizedBox.shrink()
                        : Transform.translate(
                            offset: Offset(
                              0,
                              (isLandscape ? -18 : -26) + spectatorBoardDrop,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 260),
                              child: state.phase == 'trick_end'
                                  ? _buildTrickEndArea(state)
                                  : _buildTrickArea(state, game),
                            ),
                          ),
                  ),
                ),
                for (int i = 0; i < state.players.length; i++) ...[
                  () {
                    final p = state.players[i];
                    final angle = _mightySpectatorSeatAngleForIndex(
                      i,
                      state.players.length,
                    );
                    final seatLift = _mightySeatVerticalLift(
                      angle,
                      isLandscape: isLandscape,
                      spectatorMode: true,
                    );
                    final seatLeft =
                        centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
                    final seatTop =
                        centerY +
                        seatRadiusY * math.sin(angle) -
                        seatHeight / 2 -
                        seatLift;
                    return Positioned(
                      left: seatLeft,
                      top: seatTop,
                      width: seatWidth,
                      height: seatHeight,
                      child: _buildTableSeatCard(
                        state,
                        game,
                        p,
                        canRequestCardView: canRequestCardView,
                        highlighted:
                            _viewingPlayerId == p.id &&
                            game.approvedCardViews.contains(p.id) &&
                            p.canViewCards,
                      ),
                    );
                  }(),
                ],
                if (!isBidding)
                  for (int i = 0; i < state.players.length; i++) ...[
                    () {
                      final p = state.players[i];
                      final angle = _mightySpectatorSeatAngleForIndex(
                        i,
                        state.players.length,
                      );
                      final seatLift = _mightySeatVerticalLift(
                        angle,
                        isLandscape: isLandscape,
                        spectatorMode: true,
                      );
                      final seatLeft =
                          centerX +
                          seatRadiusX * math.cos(angle) -
                          seatWidth / 2;
                      final seatTop =
                          centerY +
                          seatRadiusY * math.sin(angle) -
                          seatHeight / 2 -
                          seatLift;
                      final trickPlay = activeTrick
                          .cast<MightyTrickPlay?>()
                          .firstWhere(
                            (play) => play?.playerId == p.id,
                            orElse: () => null,
                          );
                      if (trickPlay == null) return const SizedBox.shrink();
                      return Positioned(
                        left: seatLeft + (seatWidth - playedCardWidth) / 2,
                        top: seatTop + seatHeight + 2,
                        child: _buildTablePlayedCard(
                          state,
                          trickPlay,
                          width: playedCardWidth,
                          height: playedCardHeight,
                          isWinner:
                              winnerId != null &&
                              trickPlay.playerId == winnerId,
                        ),
                      );
                    }(),
                  ],
              ],
            );
          }

          final opponents = visiblePlayers;
          final opponentCount = opponents.length;
          final centerY =
              (isLandscape ? height * 0.39 : height * 0.41) + playerBoardDrop;
          final maxSeatRadiusX = math.max(0.0, centerX - seatWidth / 2 - 10);
          final seatRadiusX = math.min(
            width * _mightySeatRadiusXFactor(opponentCount),
            math.min(
              _mightySeatRadiusXCap(width, opponentCount, spectator: false),
              maxSeatRadiusX,
            ),
          );
          final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 6);
          final seatRadiusY = math.min(
            height * (isLandscape ? 0.35 : 0.36),
            math.min(
              _mightySeatRadiusYCap(height, spectator: false),
              maxSeatRadiusY,
            ),
          );
          final bottomMostOpponentCardTop = opponents.isEmpty
              ? centerY
              : List.generate(
                  opponents.length,
                  (i) =>
                      centerY +
                      seatRadiusY *
                          math.sin(
                            _mightyTopSeatAngleForIndex(i, opponents.length),
                          ) +
                      _mightySmallDeviceSideSeatDrop(
                        _mightyTopSeatAngleForIndex(i, opponents.length),
                        width: width,
                        playerCount: opponents.length,
                        spectatorMode: false,
                        isLandscape: isLandscape,
                      ) +
                      seatHeight / 2 +
                      2,
                ).reduce(math.max);
          final centerLowerBound = height * (isLandscape ? 0.60 : 0.64);
          final selfCardTop = math.min(
            height - 60,
            math.max(bottomMostOpponentCardTop + 40, centerLowerBound),
          );

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment(
                    0,
                    isBidding || isKillSelect
                        ? 0.10
                        : (isLandscape ? 0.36 : 0.46),
                  ),
                  child: isBidding || isKillSelect
                      ? const SizedBox.shrink()
                      : Transform.translate(
                          offset: Offset(
                            0,
                            (isLandscape ? -18 : -26) + playerBoardDrop,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: state.phase == 'trick_end'
                                ? _buildTrickEndArea(state)
                                : _buildTrickArea(state, game),
                          ),
                        ),
                ),
              ),
              for (int i = 0; i < opponents.length; i++) ...[
                () {
                  final p = opponents[i];
                  final angle = _mightyTopSeatAngleForIndex(
                    i,
                    opponents.length,
                  );
                  final seatLift = _mightySeatVerticalLift(
                    angle,
                    isLandscape: isLandscape,
                  );
                  final seatLeft =
                      centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
                  final seatTop =
                      centerY +
                      seatRadiusY * math.sin(angle) -
                      seatHeight / 2 -
                      seatLift +
                      _mightySmallDeviceSideSeatDrop(
                        angle,
                        width: width,
                        playerCount: opponents.length,
                        spectatorMode: false,
                        isLandscape: isLandscape,
                      );
                  return Positioned(
                    left: seatLeft,
                    top: seatTop,
                    width: seatWidth,
                    height: seatHeight,
                    child: _buildTableSeatCard(
                      state,
                      game,
                      p,
                      canRequestCardView: canRequestCardView,
                    ),
                  );
                }(),
              ],
              if (!isBidding)
                for (int i = 0; i < opponents.length; i++) ...[
                  () {
                    final p = opponents[i];
                    final angle = _mightyTopSeatAngleForIndex(
                      i,
                      opponents.length,
                    );
                    final seatLift = _mightySeatVerticalLift(
                      angle,
                      isLandscape: isLandscape,
                    );
                    final seatLeft =
                        centerX + seatRadiusX * math.cos(angle) - seatWidth / 2;
                    final seatTop =
                        centerY +
                        seatRadiusY * math.sin(angle) -
                        seatHeight / 2 -
                        seatLift +
                        _mightySmallDeviceSideSeatDrop(
                          angle,
                          width: width,
                          playerCount: opponents.length,
                          spectatorMode: false,
                          isLandscape: isLandscape,
                        );
                    final trickPlay = activeTrick
                        .cast<MightyTrickPlay?>()
                        .firstWhere(
                          (play) => play?.playerId == p.id,
                          orElse: () => null,
                        );
                    if (trickPlay == null) return const SizedBox.shrink();
                    return Positioned(
                      left: seatLeft + (seatWidth - playedCardWidth) / 2,
                      top: seatTop + seatHeight + 2,
                      child: _buildTablePlayedCard(
                        state,
                        trickPlay,
                        width: playedCardWidth,
                        height: playedCardHeight,
                        isWinner:
                            winnerId != null && trickPlay.playerId == winnerId,
                      ),
                    );
                  }(),
                ],
              if (!isBidding && selfPlay != null)
                Positioned(
                  left: centerX - playedCardWidth / 2,
                  top: selfCardTop,
                  child: _buildTablePlayedCard(
                    state,
                    selfPlay,
                    width: playedCardWidth,
                    height: playedCardHeight,
                    isWinner: winnerId != null && selfPlay.playerId == winnerId,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveBoardStage(MightyGameStateData state, GameService game) {
    final showBottomOverlay = state.phase != 'game_end';
    final bottomOverlay = showBottomOverlay
        ? _buildHandArea(state, game)
        : const SizedBox.shrink();
    final bottomInset = !showBottomOverlay
        ? 0.0
        : game.isSpectator
        ? 110.0
        : 230.0;

    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: _buildTableBoard(state, game),
          ),
        ),
        // round_end / game_end dim + result UI are rendered at the body-level
        // Stack so the dim extends edge-to-edge through the SafeArea.
        if (state.phase == 'kitty_exchange')
          Positioned(
            left: 12,
            right: 12,
            bottom: game.isSpectator ? 120 : 210,
            child: _buildKittyUI(game, state),
          ),
        if (showBottomOverlay)
          Align(alignment: Alignment.bottomCenter, child: bottomOverlay),
      ],
    );
  }

  Widget _buildTableSeatCard(
    MightyGameStateData state,
    GameService game,
    MightyPlayer player, {
    required bool canRequestCardView,
    bool highlighted = false,
  }) {
    final isCurrentTurn = player.id == state.currentPlayer;
    final isDeclarer = player.id == state.declarer;
    final isPartner = state.friendRevealed && player.id == state.partner;
    final isExcluded = state.excludedPlayers.contains(player.id);
    final isGovt =
        player.id == state.declarer ||
        (state.friendRevealed && player.id == state.partner);
    final hasPointCards = !isGovt && player.pointCards.isNotEmpty;
    final isPending =
        canRequestCardView && game.pendingCardViewRequests.contains(player.id);
    final isApproved =
        canRequestCardView &&
        game.approvedCardViews.contains(player.id) &&
        player.canViewCards;

    Widget? roleLabel;
    if (isExcluded) {
      roleLabel = Text(
        L10n.of(context).mtKillExcluded,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: Color(0xFFD84315),
        ),
      );
    } else if (isDeclarer) {
      roleLabel = Text(
        L10n.of(context).mtDeclarer,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: Color(0xFFFF8A00),
        ),
      );
    } else if (isPartner) {
      roleLabel = Text(
        L10n.of(context).mtFriend,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4CAF50),
        ),
      );
    } else if (state.phase == 'bidding' && player.bid != null) {
      roleLabel = _bidScoreboardBadge(player.bid);
    }

    return Opacity(
      opacity: isExcluded ? 0.45 : 1.0,
      child: GestureDetector(
        onTap: () => _handleTableSeatTap(
          state,
          game,
          player,
          canRequestCardView: canRequestCardView,
          hasPointCards: hasPointCards,
          isApproved: isApproved,
          isPending: isPending,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact =
                constraints.maxHeight <= 70 || constraints.maxWidth <= 96;
            final horizontalPadding = compact ? 5.0 : 7.0;
            final verticalPadding = compact ? 4.0 : 6.0;
            final timeoutHeight = compact ? 11.0 : 12.0;
            final dotSize = compact ? 5.0 : 6.0;
            final offlineIconSize = compact ? 10.0 : 11.0;
            final nameFontSize = compact ? 10.0 : 11.0;
            final scoreFontSize = compact ? 13.0 : 15.0;
            final metaFontSize = compact ? 8.0 : 8.5;
            final spacing = compact ? 1.0 : 2.0;
            final contentWidth = math.max(
              28.0,
              (constraints.maxWidth - horizontalPadding * 2) * 0.7,
            );
            final labelTint = highlighted
                ? const Color(0xFFE7F2FF).withValues(alpha: 0.92)
                : isCurrentTurn
                ? const Color(0xFFFFF0C9).withValues(alpha: 0.88)
                : const Color(0xFFFFFCFA).withValues(alpha: 0.64);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  decoration: const BoxDecoration(),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: compact ? 6 : 8,
                              vertical: compact ? 4 : 5,
                            ),
                            decoration: BoxDecoration(
                              color: labelTint,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  isCurrentTurn ||
                                      isDeclarer ||
                                      isPartner ||
                                      highlighted
                                  ? Border.all(
                                      color: isCurrentTurn
                                          ? const Color(0xFFE6C86A)
                                          : isDeclarer
                                          ? const Color(0xFFFF8A00)
                                          : isPartner
                                          ? const Color(0xFF4CAF50)
                                          : const Color(0xFF64B5F6),
                                      width: 1.5,
                                    )
                                  : null,
                            ),
                            child: SizedBox(
                              width: contentWidth,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    height: timeoutHeight,
                                    child: Center(child: roleLabel),
                                  ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isCurrentTurn)
                                        Container(
                                          width: dotSize,
                                          height: dotSize,
                                          margin: EdgeInsets.only(
                                            right: compact ? 3 : 4,
                                          ),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFFE6A800),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      if (!player.connected)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            right: compact ? 2 : 3,
                                          ),
                                          child: Icon(
                                            Icons.wifi_off,
                                            size: offlineIconSize,
                                            color: const Color(0xFFE53935),
                                          ),
                                        ),
                                      Flexible(
                                        child: Text(
                                          player.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: player.connected
                                                ? const Color(0xFF5A4038)
                                                : const Color(0xFFE53935),
                                            fontSize: nameFontSize,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: spacing),
                                  Text(
                                    '${state.scores[player.id] ?? 0}',
                                    style: TextStyle(
                                      color: const Color(0xFF5A4038),
                                      fontSize: scoreFontSize,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  SizedBox(height: spacing),
                                  SizedBox(
                                    height: timeoutHeight,
                                    child: player.timeoutCount > 0
                                        ? Text(
                                            '⏱ ${player.timeoutCount}/3',
                                            style: TextStyle(
                                              fontSize: metaFontSize,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFFE65100),
                                            ),
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (canRequestCardView)
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
                                      : const Color(
                                          0xFF8A7A72,
                                        ).withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          // Captured-points badge (top-left), mirroring the
                          // card-view eye on the top-right. Only shown for
                          // opposition players who have actually captured at
                          // least one point card.
                          if (hasPointCards && player.pointCount > 0)
                            Positioned(
                              left: -4,
                              top: -4,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                  minHeight: 16,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFE53935),
                                  ),
                                ),
                                child: Text(
                                  '${player.pointCount}',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFE53935),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _handleTableSeatTap(
    MightyGameStateData state,
    GameService game,
    MightyPlayer player, {
    required bool canRequestCardView,
    required bool hasPointCards,
    required bool isApproved,
    required bool isPending,
  }) {
    if (canRequestCardView) {
      if (isApproved) {
        setState(() {
          _viewingPlayerId = _viewingPlayerId == player.id ? null : player.id;
        });
      } else if (!isPending) {
        _cardViewRequestTimer?.cancel();
        game.requestCardView(player.id);
        setState(() => _viewingPlayerId = player.id);
        _cardViewRequestTimer = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          game.expireCardViewRequest(player.id);
        });
      }
      return;
    }

    if (hasPointCards &&
        (state.phase == 'playing' ||
            state.phase == 'trick_end' ||
            state.phase == 'round_end')) {
      _showPointCardsDialog(player);
      return;
    }

    _showPlayerProfileDialog(
      player.name,
      game,
      isBot: player.id.startsWith('bot_'),
    );
  }

  Widget _buildTablePlayedCard(
    MightyGameStateData state,
    MightyTrickPlay trickPlay, {
    required double width,
    required double height,
    required bool isWinner,
  }) {
    return Container(
      decoration: isWinner
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            )
          : null,
      child: PlayingCard(
        cardId: _displayCardId(trickPlay.cardId),
        width: width,
        height: height,
        isInteractive: false,
        borderColor:
            (state.trumpSuit != null &&
                state.trumpSuit != 'no_trump' &&
                _getCardSuit(trickPlay.cardId) == state.trumpSuit)
            ? PlayingCard.suitColors[_getCardSuit(trickPlay.cardId)]
            : null,
        badgeIcon: trickPlay.cardId == state.mightyCard
            ? Icons.star
            : (state.jokerCallActive && trickPlay.cardId == state.jokerCallCard)
            ? Icons.gps_fixed
            : null,
        badgeColor: trickPlay.cardId == state.mightyCard
            ? const Color(0xFFFFB300)
            : (state.jokerCallActive && trickPlay.cardId == state.jokerCallCard)
            ? const Color(0xFFE53935)
            : null,
      ),
    );
  }

  double _mightySpectatorSeatAngleForIndex(int index, int count) {
    final custom = _mightyCustomSpectatorSeatAnglesDeg(count);
    if (custom != null) return custom[index] * math.pi / 180;
    if (count <= 1) return math.pi * 1.5;
    return _mightySeatAngleForIndex(index, count, includeBottomSeat: false);
  }

  double _mightySeatAngleForIndex(
    int index,
    int playerCount, {
    bool includeBottomSeat = true,
  }) {
    if (includeBottomSeat) {
      if (index == 0) return math.pi / 2;
      final opponents = playerCount - 1;
      if (opponents <= 1) return math.pi * 1.5;
      final customOpponentAngles = _mightyCustomSeatAnglesDeg(opponents);
      if (customOpponentAngles != null) {
        return customOpponentAngles[index - 1] * math.pi / 180;
      }
      final startDeg = _mightySeatArcStartDeg(opponents);
      final endDeg = _mightySeatArcEndDeg(opponents);
      final progress = (index - 1) / (opponents - 1);
      final angleDeg = startDeg + (endDeg - startDeg) * progress;
      return angleDeg * math.pi / 180;
    }

    if (playerCount <= 1) return math.pi * 1.5;
    final customAngles = _mightyCustomSeatAnglesDeg(playerCount);
    if (customAngles != null) {
      return customAngles[index] * math.pi / 180;
    }
    final startDeg = _mightySeatArcStartDeg(playerCount);
    final endDeg = _mightySeatArcEndDeg(playerCount);
    final progress = index / (playerCount - 1);
    final angleDeg = startDeg + (endDeg - startDeg) * progress;
    return angleDeg * math.pi / 180;
  }

  double _mightyTopSeatAngleForIndex(int index, int playerCount) {
    if (playerCount <= 1) return math.pi * 1.5;
    final customAngles = _mightyCustomSeatAnglesDeg(playerCount);
    if (customAngles != null) {
      return customAngles[index] * math.pi / 180;
    }
    final startDeg = _mightySeatArcStartDeg(playerCount);
    final endDeg = _mightySeatArcEndDeg(playerCount);
    final progress = index / (playerCount - 1);
    final angleDeg = startDeg + (endDeg - startDeg) * progress;
    return angleDeg * math.pi / 180;
  }

  List<double>? _mightyCustomSeatAnglesDeg(int count) {
    switch (count) {
      case 4:
        return const [172, 238, 302, 368];
      default:
        return null;
    }
  }

  List<double>? _mightyCustomSpectatorSeatAnglesDeg(int count) {
    switch (count) {
      case 6:
        return const [142, 188, 236, 304, 352, 398];
      default:
        return null;
    }
  }

  double _mightySeatRadiusXFactor(int count) {
    if (count >= 5) return 0.44;
    if (count == 4) return 0.43;
    if (count == 3) return 0.40;
    return 0.38;
  }

  double _mightySeatRadiusXCap(
    double width,
    int count, {
    required bool spectator,
  }) {
    final base = spectator
        ? (count >= 5 ? 228.0 : 182.0)
        : (count >= 5 ? 236.0 : 188.0);
    if (width >= 1200) return base + 130;
    if (width >= 900) return base + 90;
    if (width >= 700) return base + 45;
    return base;
  }

  double _mightySeatRadiusYCap(double height, {required bool spectator}) {
    final base = spectator ? 196.0 : 202.0;
    if (height >= 1100) return base + 90;
    if (height >= 850) return base + 50;
    if (height >= 700) return base + 24;
    return base;
  }

  double _mightySeatVerticalLift(
    double angle, {
    required bool isLandscape,
    bool spectatorMode = false,
  }) {
    final cornerWeight = math.pow(math.cos(angle).abs(), 1.15).toDouble();
    final lowerCornerWeight = math.max(0.0, math.sin(angle));
    final baseLift =
        cornerWeight * (isLandscape ? 24.0 : 30.0) +
        lowerCornerWeight * (isLandscape ? 10.0 : 14.0);
    if (!spectatorMode) return baseLift;
    final upperWeight = math.max(0.0, -math.sin(angle));
    final reduction = (1 - upperWeight) * (isLandscape ? 12.0 : 18.0);
    return math.max(0.0, baseLift - reduction);
  }

  double _mightySmallDeviceSideSeatDrop(
    double angle, {
    required double width,
    required int playerCount,
    required bool spectatorMode,
    required bool isLandscape,
  }) {
    if (spectatorMode || isLandscape || playerCount != 4 || width > 430) {
      return 0.0;
    }
    final horizontalWeight = (1 - (math.sin(angle).abs() / 0.45)).clamp(
      0.0,
      1.0,
    );
    return 10.0 * horizontalWeight;
  }

  double _mightySmallDeviceBoardDrop({
    required double width,
    required int playerCount,
    required bool spectatorMode,
    required bool isLandscape,
  }) {
    if (spectatorMode || isLandscape || width > 430 || playerCount != 5) {
      return 0.0;
    }
    return 18.0;
  }

  double _mightySeatArcStartDeg(int count) {
    if (count >= 5) return 145.0;
    if (count == 4) return 198.0;
    if (count == 3) return 210.0;
    return 225.0;
  }

  double _mightySeatArcEndDeg(int count) {
    if (count >= 5) return 395.0;
    if (count == 4) return 342.0;
    if (count == 3) return 330.0;
    return 315.0;
  }

  Widget _buildOppositionPointBar(MightyGameStateData state) {
    // Collect all opposition point cards
    final oppCards = <String>[];
    int oppPoints = 0;
    for (final p in state.players) {
      final isGovt =
          p.id == state.declarer ||
          (state.friendRevealed && p.id == state.partner);
      if (!isGovt) {
        oppCards.addAll(p.pointCards);
        oppPoints += p.pointCount;
      }
    }
    final bidPoints = (state.currentBid['points'] is num)
        ? (state.currentBid['points'] as num).toInt()
        : 13;
    // Opposition needs (20 - bidPoints + 1) to defeat declarer
    final oppTarget = 20 - bidPoints + 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          // Label with opposition points captured (e.g. "야당 13")
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: oppPoints >= oppTarget
                  ? const Color(0xFFE53935)
                  : const Color(0xFF8A7A72),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${L10n.of(context).mtOpposition} $oppPoints',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Scrollable card list
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: oppCards
                    .map(
                      (cardId) => Padding(
                        padding: const EdgeInsets.only(right: 3),
                        child: PlayingCard(
                          cardId: _displayCardId(cardId),
                          width: 24,
                          height: 34,
                          isInteractive: false,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPointCardsDialog(MightyPlayer p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          L10n.of(context).mtPointCardsTitle(p.name, p.pointCount),
          style: const TextStyle(fontSize: 15),
        ),
        content: p.pointCards.isEmpty
            ? Text(L10n.of(context).mtNoPointCards)
            : Wrap(
                spacing: 6,
                runSpacing: 6,
                children: p.pointCards
                    .map(
                      (cardId) => PlayingCard(
                        cardId: _displayCardId(cardId),
                        width: 42,
                        height: 59,
                        isInteractive: false,
                      ),
                    )
                    .toList(),
              ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).mtClose),
          ),
        ],
      ),
    );
  }

  // ── Trick Area ──
  Widget _buildTrickArea(MightyGameStateData state, GameService game) {
    if (state.currentTrick.isEmpty) {
      return Center(
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.style, size: 20, color: Color(0xFF8A7A72)),
              const SizedBox(height: 4),
              Text(
                state.isMyTurn
                    ? L10n.of(context).mtYourTurn
                    : L10n.of(context).mtWaiting,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              if (_remainingSeconds > 0 && state.isMyTurn)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${_remainingSeconds}s',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _remainingSeconds <= 5
                          ? const Color(0xFFE53935)
                          : const Color(0xFF8A7A72),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    // Lead suit from first card in trick
    String? leadSuit;
    final leadCardId = state.currentTrick.first.cardId;
    if (leadCardId == 'mighty_joker') {
      leadSuit = state.jokerSuitDeclared;
    } else {
      leadSuit = _getCardSuit(leadCardId);
    }

    // Declarer's contract (suit + points)
    final contractPoints = state.currentBid['points'] as int?;
    final contractSuit = state.currentBid['suit']?.toString();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Line 1: contract (declarer's trump + bid points)
            if (contractPoints != null && contractSuit != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SuitIcon(
                    suit: contractSuit,
                    size: 15,
                    color: _bidAccentColor(contractSuit),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    L10n.of(context).mtContractWithPoints(contractPoints),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _bidAccentColor(contractSuit),
                    ),
                  ),
                ],
              ),
            // Line 2: lead suit
            if (leadSuit != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${L10n.of(context).mtLead} ',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _bidAccentColor(leadSuit),
                      ),
                    ),
                    SuitIcon(
                      suit: leadSuit,
                      size: 13,
                      color: _bidAccentColor(leadSuit),
                    ),
                  ],
                ),
              ),
            // Line 3: turn timer
            if (_remainingSeconds > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_remainingSeconds}s',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _remainingSeconds <= 5
                        ? const Color(0xFFE53935)
                        : const Color(0xFF8A7A72),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Trick End Area ──
  Widget _buildTrickEndArea(MightyGameStateData state) {
    final winnerName =
        state.players
            .where((p) => p.id == state.lastTrickWinner)
            .map((p) => p.name)
            .firstOrNull ??
        '';
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                L10n.of(context).mtWins(winnerName),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF4CAF50),
                ),
              ),
            ),
            if (state.friendCard != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _buildFriendRevealLine(state),
              ),
          ],
        ),
      ),
    );
  }

  /// Renders a friend card (e.g. selected friend in the kitty UI) as a small
  /// Row of SuitIcon + rank text, falling back to a plain Text widget for
  /// special variants (joker / no-friend / first-trick) where no suit applies.
  Widget _buildFriendCardInline(
    String cardId, {
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    final l10n = L10n.of(context);
    if (cardId == 'mighty_joker') {
      return Text(
        l10n.mtFriendCardJoker,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: const Color(0xFF7B1FA2),
        ),
      );
    }
    if (cardId == 'no_friend') {
      return Text(
        l10n.mtFriendCardSolo,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: const Color(0xFF8A7A72),
        ),
      );
    }
    if (cardId == 'first_trick') {
      return Text(
        l10n.mtFriendCard1st,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: const Color(0xFF1565C0),
        ),
      );
    }
    final parts = cardId.replaceFirst('mighty_', '').split('_');
    if (parts.length != 2) {
      return Text(
        cardId,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: const Color(0xFF5A4038),
        ),
      );
    }
    final suit = parts[0];
    final rank = parts[1];
    final accent = _bidAccentColor(suit);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SuitIcon(suit: suit, size: fontSize, color: accent),
        const SizedBox(width: 2),
        Text(
          rank,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: accent,
          ),
        ),
      ],
    );
  }

  /// Builds the friend-card line shown in the trick-end area. Uses SuitIcon
  /// + suit-colored text when the friend is a regular card; falls back to
  /// neutral text for joker / no-friend / first-trick variants.
  Widget _buildFriendRevealLine(MightyGameStateData state) {
    final l10n = L10n.of(context);
    final friendCard = state.friendCard!;
    final partnerName = state.partner == null
        ? ''
        : state.players
                  .where((p) => p.id == state.partner)
                  .map((p) => p.name)
                  .firstOrNull ??
              '';
    final showReveal = state.friendRevealed && state.partner != null;

    String? suit;
    String? rank;
    String specialLabel = '';
    if (friendCard == 'mighty_joker') {
      specialLabel = l10n.mtFriendCardJoker;
    } else if (friendCard == 'no_friend') {
      specialLabel = l10n.mtFriendCardSolo;
    } else if (friendCard == 'first_trick') {
      specialLabel = l10n.mtFriendCard1st;
    } else {
      final parts = friendCard.replaceFirst('mighty_', '').split('_');
      if (parts.length == 2) {
        suit = parts[0];
        rank = parts[1];
      } else {
        specialLabel = friendCard;
      }
    }
    final accent = suit != null
        ? _bidAccentColor(suit)
        : const Color(0xFF8A7A72);
    final baseStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: accent,
    );
    const cardSentinel = 'CARD';
    final template = showReveal
        ? l10n.mtFriendRevealed(cardSentinel, partnerName)
        : l10n.mtFriendHidden(cardSentinel);
    final parts = template.split(cardSentinel);
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: baseStyle,
        children: [
          if (parts.isNotEmpty) TextSpan(text: parts[0]),
          if (suit != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: SuitIcon(suit: suit, size: 11, color: accent),
            ),
            TextSpan(text: rank!),
          ] else
            TextSpan(text: specialLabel),
          if (parts.length > 1) TextSpan(text: parts[1]),
        ],
      ),
    );
  }

  // Sentinel used to insert a SuitIcon into a localized message that takes
  // a {suit} placeholder. Picked so it won't collide with real translations.
  static const String _trumpChangeSentinel = ' SUIT ';

  /// Builds an alert-dialog body for the trump-change confirm flow. The
  /// localized text contains [_trumpChangeSentinel] where the suit should
  /// appear; we split on that and inject a SuitIcon inline.
  Widget _buildTrumpChangeConfirmBody({
    required String suit,
    required String bodyText,
  }) {
    final parts = bodyText.split(_trumpChangeSentinel);
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: Color(0xFF5A4038)),
        children: [
          if (parts.isNotEmpty) TextSpan(text: parts[0]),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SuitIcon(
              suit: suit,
              size: 13,
              color: _bidAccentColor(suit),
            ),
          ),
          if (parts.length > 1) TextSpan(text: parts[1]),
        ],
      ),
    );
  }

  /// Shared Yes/No confirm dialog used by bid-raise and trump-change so the
  /// player never accidentally bumps their bid with a one-tap slip.
  Future<bool> _confirmBidAction({
    required String title,
    required Widget body,
  }) async {
    final l10n = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: DefaultTextStyle.merge(
          style: const TextStyle(fontSize: 13, color: Color(0xFF5A4038)),
          child: body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.mtCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1565C0),
            ),
            child: Text(l10n.mtConfirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmDealMiss(GameService game) async {
    final l10n = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          l10n.mtDealMiss,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        content: Text(
          l10n.mtDealMissConfirmBody,
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.mtCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD84315),
            ),
            child: Text(l10n.mtDealMiss),
          ),
        ],
      ),
    );
    if (ok == true) {
      game.mightyDeclareDealMiss();
    }
  }

  // Accent color for bid-related UI elements. Maps each suit to its card
  // color, NT to a distinct purple, and an unknown/missing suit to a neutral
  // brown so the call sites don't have to repeat the ternary.
  Color _bidAccentColor(String? suit) {
    if (suit == 'no_trump') return const Color(0xFF7B1FA2);
    return PlayingCard.suitColors[suit] ?? const Color(0xFF5A4038);
  }

  Widget _buildSuitChip(
    String suit,
    String label,
    Color color, {
    bool enabled = true,
    VoidCallback? onTap,
  }) {
    final isSelected = _bidSuit == suit;
    final effectiveColor = enabled ? color : const Color(0xFFBDBDBD);
    return GestureDetector(
      onTap: enabled ? (onTap ?? () => setState(() => _bidSuit = suit)) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected && enabled
              ? color.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected && enabled ? color : const Color(0xFFE0D8D4),
            width: isSelected && enabled ? 2 : 1,
          ),
        ),
        child: suit == 'no_trump'
            ? Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  color: effectiveColor,
                  fontWeight: isSelected && enabled
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              )
            : SuitIcon(suit: suit, size: 20, color: effectiveColor),
      ),
    );
  }

  // ── Kitty Exchange ──
  Widget _buildKittyUI(GameService game, MightyGameStateData state) {
    if (!state.isMyTurn) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Text(
          L10n.of(context).mtExchangingKitty,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: Color(0xFF5A4038)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Material(
                  color: const Color(0xFFFB8C00),
                  borderRadius: BorderRadius.circular(12),
                  elevation: 1,
                  child: InkWell(
                    onTap: () => _showContractChangeDialog(game),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.tune, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            L10n.of(context).mtChangeContract,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (_remainingSeconds > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _remainingSeconds <= 5
                        ? const Color(0xFFFFEBEE)
                        : Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _remainingSeconds <= 5
                          ? const Color(0xFFE53935)
                          : const Color(0xFFE0D8D4),
                    ),
                  ),
                  child: Text(
                    '${_remainingSeconds}s',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _remainingSeconds <= 5
                          ? const Color(0xFFE53935)
                          : const Color(0xFF5A4038),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.swap_horiz, size: 18, color: Color(0xFF5A4038)),
              const SizedBox(width: 6),
              Text(
                L10n.of(context).mtDiscard3,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _discardSelection.length == 3
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_discardSelection.length}/3',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _discardSelection.length == 3
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF8A7A72),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            L10n.of(context).mtFriendColon,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const SizedBox(height: 6),
          // Step 1: Friend mode
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildFriendModeChip('no_friend', L10n.of(context).mtNoFriend),
              _buildFriendModeChip('first_trick', L10n.of(context).mt1stTrick),
              _buildFriendModeChip('joker', L10n.of(context).mtJoker),
              _buildFriendModeChip('card', L10n.of(context).mtCard),
            ],
          ),
          // Step 2: If card mode, pick suit + rank
          if (_friendMode == 'card') ...[
            const SizedBox(height: 8),
            // Suit row
            Row(
              children: [
                for (final suit in ['spade', 'heart', 'diamond', 'club'])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _friendSuit = suit;
                        _syncFriendCardSelection(state);
                      }),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _friendSuit == suit
                              ? const Color(0xFFE3F2FD)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _friendSuit == suit
                                ? const Color(0xFF1565C0)
                                : const Color(0xFFE0D8D4),
                            width: _friendSuit == suit ? 2 : 1,
                          ),
                        ),
                        child: Center(child: SuitIcon(suit: suit, size: 18)),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Rank row
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final rank in [
                  'A',
                  'K',
                  'Q',
                  'J',
                  '10',
                  '9',
                  '8',
                  '7',
                  '6',
                  '5',
                  '4',
                  '3',
                  '2',
                ])
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _friendRank = rank;
                        _syncFriendCardSelection(state);
                      });
                    },
                    child: Container(
                      width: 36,
                      height: 30,
                      decoration: BoxDecoration(
                        color: _friendRank == rank
                            ? const Color(0xFFE3F2FD)
                            : const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _friendRank == rank
                              ? const Color(0xFF1565C0)
                              : const Color(0xFFE0D8D4),
                          width: _friendRank == rank ? 2 : 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          rank,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _friendRank == rank
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: const Color(0xFF5A4038),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            // Show selected card label (with SuitIcon for regular cards).
            if (_friendCardSelection.isNotEmpty) ...[
              const SizedBox(height: 6),
              _buildFriendCardInline(_friendCardSelection),
            ],
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed:
                  _discardSelection.length == 3 &&
                      _friendMode.isNotEmpty &&
                      _friendCardSelection.isNotEmpty
                  ? () {
                      game.mightyDiscardKitty(
                        _discardSelection.toList(),
                        _friendCardSelection,
                      );
                      setState(() => _discardSelection.clear());
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(L10n.of(context).mtConfirm),
            ),
          ),
        ],
      ),
    );
  }

  void _syncFriendCardSelection(MightyGameStateData state) {
    if (_friendMode == 'card') {
      final cardId = 'mighty_${_friendSuit}_$_friendRank';
      _friendCardSelection = cardId;
      _discardSelection.remove(cardId);
    }
  }

  Widget _buildFriendModeChip(String mode, String label) {
    final isSelected = _friendMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _friendMode = mode;
        if (mode == 'no_friend') {
          _friendCardSelection = 'no_friend';
        } else if (mode == 'first_trick') {
          _friendCardSelection = 'first_trick';
        } else if (mode == 'joker') {
          _friendCardSelection = 'mighty_joker';
        } else {
          // card mode: compose from suit + rank
          _friendCardSelection = 'mighty_${_friendSuit}_$_friendRank';
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE3F2FD) : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF1565C0)
                : const Color(0xFFE0D8D4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? const Color(0xFF1565C0)
                : const Color(0xFF5A4038),
          ),
        ),
      ),
    );
  }

  // Opens a popup containing the bid/trump adjustment controls. The popup
  // auto-closes once the declarer applies a change (server confirms state).
  void _showContractChangeDialog(GameService game) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 48,
          ),
          child: Consumer<GameService>(
            builder: (_, g, _) {
              final s = g.mightyGameState;
              if (s == null || s.phase != 'kitty_exchange' || !s.isMyTurn) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (Navigator.of(dialogCtx).canPop()) {
                    Navigator.of(dialogCtx).pop();
                  }
                });
                return const SizedBox.shrink();
              }
              void closeDialog() {
                if (Navigator.of(dialogCtx).canPop()) {
                  Navigator.of(dialogCtx).pop();
                }
              }

              return Container(
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBF5),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFFB8C00,
                              ).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.tune,
                              size: 18,
                              color: Color(0xFFE65100),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              L10n.of(dialogCtx).mtChangeContract,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF5A4038),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: closeDialog,
                            icon: const Icon(Icons.close, size: 22),
                            color: const Color(0xFF8A7A72),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFEFE5DD)),
                    // Body. StatefulBuilder gives the popup its own rebuild
                    // channel so suit-chip taps (which update the screen-level
                    // _selectedTrumpSuit field) refresh the dialog too — the
                    // dialog lives in a separate Overlay route and wouldn't
                    // otherwise rebuild when the screen's setState fires.
                    StatefulBuilder(
                      builder: (_, setDialogState) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: _buildTrumpChangePanel(
                          s,
                          g,
                          onApplied: closeDialog,
                          dialogSetState: setDialogState,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ── Bid / Trump Adjustment Panel (shown inside the contract-change popup) ──
  Widget _buildTrumpChangePanel(
    MightyGameStateData state,
    GameService game, {
    VoidCallback? onApplied,
    StateSetter? dialogSetState,
  }) {
    if (!state.isMyTurn) return const SizedBox.shrink();
    final bidPoints = state.currentBid['points'] as int? ?? 13;
    final isAtCap = bidPoints >= 20;

    final trumpSuit = state.trumpSuit ?? 'no_trump';
    // 20-bid ceiling rules:
    //   • 20 NT is the hard ceiling — no contract change at all.
    //   • 20 with a suit — only change to 20 NT is allowed.
    final isAt20NT = isAtCap && trumpSuit == 'no_trump';
    final isAt20Suit = isAtCap && trumpSuit != 'no_trump';
    // Whenever the server confirms a trump change, resync our selection so
    // the new suit is highlighted instead of the stale pre-change one.
    if (_lastKnownTrumpSuit != null && _lastKnownTrumpSuit != trumpSuit) {
      _selectedTrumpSuit = trumpSuit;
    }
    _lastKnownTrumpSuit = trumpSuit;
    _selectedTrumpSuit ??= trumpSuit;
    final isSameTrump = _selectedTrumpSuit == trumpSuit;
    final nextBid = math.min(20, bidPoints + 2);

    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Current contract summary card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFE0B2)),
          ),
          child: Row(
            children: [
              SuitIcon(
                suit: trumpSuit,
                size: 22,
                color: _bidAccentColor(trumpSuit),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.mtContractWithPoints(bidPoints),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _bidAccentColor(trumpSuit),
                ),
              ),
              const Spacer(),
              if (isAtCap)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'MAX',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        // Raise-bid section (hidden at cap)
        if (!isAtCap) ...[
          Text(
            l10n.mtRaiseBidConfirmTitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A7A72),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton.icon(
              onPressed: () async {
                final ok = await _confirmBidAction(
                  title: l10n.mtRaiseBidConfirmTitle,
                  body: Text(l10n.mtRaiseBidConfirmBody(nextBid.toString())),
                );
                if (ok) {
                  game.mightyRaiseBid();
                  onApplied?.call();
                }
              },
              icon: const Icon(Icons.trending_up, size: 18),
              label: Text(
                '$bidPoints → $nextBid',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1565C0),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Change-trump section
        Row(
          children: [
            Text(
              l10n.mtChangeTrump,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A7A72),
              ),
            ),
            const SizedBox(width: 8),
            // Penalty badge is hidden at 20-point cap — no penalty applies there
            // (20 suit → 20 NT is free; 20 NT admits no change at all).
            if (!isAtCap)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  l10n.mtTrumpPenalty(2),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFE53935),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final entry in [
              ('spade', '♠', const Color(0xFF2B2B2B)),
              ('heart', '♥', const Color(0xFFD24B4B)),
              ('diamond', '♦', const Color(0xFF6FB6E5)),
              ('club', '♣', const Color(0xFF4BAA6A)),
              ('no_trump', 'NT', const Color(0xFF7B1FA2)),
            ])
              Builder(
                builder: (_) {
                  // Chip lock-out rules at 20-bid ceiling:
                  //   20 NT — every chip disabled (no change allowed).
                  //   20 suit — only the NT chip is tappable.
                  final chipDisabled =
                      isAt20NT || (isAt20Suit && entry.$1 != 'no_trump');
                  final isSelected = _selectedTrumpSuit == entry.$1;
                  return Expanded(
                    child: GestureDetector(
                      onTap: chipDisabled
                          ? null
                          : () {
                              _selectedTrumpSuit = entry.$1;
                              // Rebuild both the screen (so the field persists in
                              // State) and the dialog (so the chip highlight updates).
                              setState(() {});
                              dialogSetState?.call(() {});
                            },
                      child: Opacity(
                        opacity: chipDisabled ? 0.35 : 1.0,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 120),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? entry.$3.withValues(alpha: 0.16)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? entry.$3
                                  : entry.$1 == trumpSuit
                                  ? entry.$3.withValues(alpha: 0.5)
                                  : const Color(0xFFE0D8D4),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Center(
                            child: entry.$1 == 'no_trump'
                                ? Text(
                                    entry.$2,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: entry.$3,
                                      fontWeight:
                                          isSelected || entry.$1 == trumpSuit
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  )
                                : SuitIcon(
                                    suit: entry.$1,
                                    size: 22,
                                    color: entry.$3,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: Builder(
            builder: (_) {
              // Apply-button gating:
              //   • same trump at cap — nothing to do
              //   • 20 NT — no contract change of any kind
              //   • 20 suit — only a switch to NT is permitted
              final applyDisabled =
                  (isSameTrump && isAtCap) ||
                  isAt20NT ||
                  (isAt20Suit && _selectedTrumpSuit != 'no_trump');
              return FilledButton(
                onPressed: applyDisabled
                    ? null
                    : () async {
                        final ok = isSameTrump
                            ? await _confirmBidAction(
                                title: l10n.mtRaiseBidConfirmTitle,
                                body: Text(
                                  l10n.mtRaiseBidConfirmBody(
                                    nextBid.toString(),
                                  ),
                                ),
                              )
                            : await _confirmBidAction(
                                title: l10n.mtChangeTrumpConfirmTitle,
                                // 20 suit → 20 NT is the one change-path at cap —
                                // server applies no penalty, so the confirm body
                                // must not say "raise the bid".
                                body: _buildTrumpChangeConfirmBody(
                                  suit: _selectedTrumpSuit!,
                                  bodyText: isAt20Suit
                                      ? l10n.mtChangeTrumpNoPenaltyBody(
                                          _trumpChangeSentinel,
                                        )
                                      : l10n.mtChangeTrumpConfirmBody(
                                          _trumpChangeSentinel,
                                          nextBid.toString(),
                                        ),
                                ),
                              );
                        if (!ok) return;
                        if (isSameTrump) {
                          game.mightyRaiseBid();
                        } else {
                          game.mightyChangeTrump(_selectedTrumpSuit!);
                        }
                        setState(() => _selectedTrumpSuit = null);
                        onApplied?.call();
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: applyDisabled
                      ? const Color(0xFFBDBDBD)
                      : (isSameTrump
                            ? const Color(0xFF1565C0)
                            : const Color(0xFFE65100)),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  isAtCap
                      ? l10n.mtChangeTrump
                      : (isSameTrump
                            ? '$bidPoints → $nextBid'
                            : l10n.mtChangeTrump),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Spectator Hand View ──
  Widget _buildSpectatorHandArea(MightyGameStateData state, GameService game) {
    final viewingPlayer = _viewingPlayerId == null
        ? null
        : state.players.cast<MightyPlayer?>().firstWhere(
            (p) => p?.id == _viewingPlayerId,
            orElse: () => null,
          );
    final isApproved =
        viewingPlayer != null &&
        game.approvedCardViews.contains(viewingPlayer.id) &&
        viewingPlayer.canViewCards;
    final isPending =
        viewingPlayer != null &&
        game.pendingCardViewRequests.contains(viewingPlayer.id);

    final baseDeco = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.85),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
    );

    if (viewingPlayer == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: baseDeco,
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

    if (isPending && !isApproved) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: baseDeco,
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
              L10n.of(context).skGameRequestingCardView(viewingPlayer.name),
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

    if (isApproved) {
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: const Border(top: BorderSide(color: Color(0xFFE0D8D4))),
        ),
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
                      L10n.of(context).skGamePlayerHand(viewingPlayer.name),
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
            if (viewingPlayer.cards.isEmpty)
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
                child: _buildHandRows(
                  viewingPlayer.cards,
                  legalCards: const {},
                  isPlaying: false,
                  isKitty: false,
                  state: state,
                ),
              ),
          ],
        ),
      );
    }

    // Rejected
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: baseDeco,
      child: Text(
        L10n.of(context).skGameCardViewRejected(viewingPlayer.name),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF8A7A72),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ── Hand Area (SK-style) ──
  Widget _buildHandArea(MightyGameStateData state, GameService game) {
    // Spectator card view
    if (game.isSpectator) {
      return _buildSpectatorHandArea(state, game);
    }
    // Killed-mighty player — reuse the spectator-style peek panel so they can
    // view any opponents they've been granted card-view permission for.
    final myId = game.playerId;
    if (myId.isNotEmpty && state.excludedPlayers.contains(myId)) {
      return _buildSpectatorHandArea(state, game);
    }
    final cards = state.myCards;
    if (cards.isEmpty) return const SizedBox(height: 20);

    final isPlaying = state.phase == 'playing' && state.isMyTurn;
    final isKitty = state.phase == 'kitty_exchange' && state.isMyTurn;
    // Pre-selection: during playing phase while it isn't our turn yet, we can
    // compute which cards WOULD be legal (based on the already-known lead
    // suit) and let the user queue one up. When the turn arrives, the server
    // will confirm legality via state.legalCards.
    final canPreselect =
        state.phase == 'playing' &&
        !state.isMyTurn &&
        state.currentTrick.isNotEmpty;
    final legalCards = state.isMyTurn
        ? state.legalCards.toSet()
        : (canPreselect ? _previewLegalCards(state) : <String>{});
    final selectedCard = _selectedCard;
    final isSelectedLegal =
        selectedCard != null && legalCards.contains(selectedCard);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: (isPlaying && state.isMyTurn)
            ? const Color(0xFFFFF6D8).withValues(alpha: 0.96)
            : Colors.white.withValues(alpha: 0.92),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: (isPlaying && state.isMyTurn)
                ? const Color(0xFFE6C86A)
                : const Color(0xFFE0D8D4),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.phase == 'bidding')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildCompactBiddingPanel(state, game),
            ),
          if (state.phase == 'kill_select')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildCompactKillPanel(state, game),
            ),
          if (game.myTimeoutCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _buildTimeoutResetChip(game),
            ),
          // Top-right action strip: previous-trick viewer (shop-gated) and
          // setting declaration (server-gated on hand strength). Only
          // shown during active play phases.
          if (state.phase == 'playing' ||
              state.phase == 'trick_end' ||
              state.phase == 'round_end')
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (state.canDeclareSetting) _buildSettingButton(game),
                  if (state.canDeclareSetting &&
                      game.hasMightyPrevTrick &&
                      state.tricks.isNotEmpty)
                    const SizedBox(width: 6),
                  if (game.hasMightyPrevTrick && state.tricks.isNotEmpty)
                    _buildPrevTrickButton(state),
                ],
              ),
            ),
          // Play button — blocked when leading the joker without a declared
          // suit (the suit selector sits just below the hand; user must pick).
          if (isPlaying &&
              selectedCard != null &&
              isSelectedLegal &&
              !(selectedCard == 'mighty_joker' &&
                  state.currentTrick.isEmpty &&
                  _jokerSuitChoice == null))
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
              child: SizedBox(
                width: double.infinity,
                height: 42,
                child: FilledButton.icon(
                  onPressed: () {
                    final isJokerCallCard = selectedCard == state.jokerCallCard;
                    game.mightyPlayCard(
                      selectedCard,
                      jokerSuit: selectedCard == 'mighty_joker'
                          ? _jokerSuitChoice
                          : null,
                      jokerCall:
                          isJokerCallCard &&
                          state.currentTrick.isEmpty &&
                          state.jokerHasPower &&
                          _jokerCallChoice,
                    );
                    setState(() {
                      _selectedCard = null;
                      _jokerSuitChoice = null;
                      _jokerCallChoice = true;
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE6F1FF),
                    foregroundColor: const Color(0xFF355D89),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 20),
                  label: Text(
                    _remainingSeconds > 0
                        ? L10n.of(context).mtPlayTimer(_remainingSeconds)
                        : L10n.of(context).mtPlay,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            )
          else if (isPlaying)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    (selectedCard == 'mighty_joker' &&
                            state.currentTrick.isEmpty &&
                            _jokerSuitChoice == null)
                        ? L10n.of(context).mtJokerSelectSuit
                        : L10n.of(context).mtSelectCard,
                    style: TextStyle(
                      color: Color(0xFF5A4038),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_remainingSeconds > 0) ...[
                    const SizedBox(width: 8),
                    Text(
                      '(${_remainingSeconds}s)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: _remainingSeconds <= 5
                            ? const Color(0xFFE53935)
                            : const Color(0xFF8A7A72),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          // Joker weak warning (first/last trick).
          // 6p kill-mighty: the killed player is excluded, so activePlayers
          // is players.length - excludedPlayers. Using the raw player count
          // here made the client think trick 8 was the last trick (50/6=8)
          // in 6p mode, mis-flagging the joker warning.
          if (isPlaying && _selectedCard == 'mighty_joker') ...[
            if (() {
              final active =
                  state.players.length - state.excludedPlayers.length;
              if (active <= 0) return false;
              final totalTricks = 50 ~/ active;
              return state.tricks.isEmpty ||
                  state.tricks.length == totalTricks - 1;
            }())
              Container(
                margin: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFFB74D)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Color(0xFFE65100),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      state.tricks.isEmpty
                          ? L10n.of(context).mtJokerLoses1st
                          : L10n.of(context).mtJokerLosesLast,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          // Joker suit selector
          if (isPlaying &&
              _selectedCard == 'mighty_joker' &&
              state.currentTrick.isEmpty)
            _buildJokerSuitSelector(),
          // Joker call toggle — hidden when joker has no power in this trick
          // (first/last trick with *JokerPower option disabled), since calling
          // the joker then is meaningless.
          if (isPlaying &&
              _selectedCard == state.jokerCallCard &&
              state.currentTrick.isEmpty &&
              state.jokerHasPower)
            _buildJokerCallToggle(),
          // Card rows
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildHandRows(
              cards,
              legalCards: legalCards,
              isPlaying: isPlaying || canPreselect,
              isKitty: isKitty,
              state: state,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactBiddingPanel(
    MightyGameStateData state,
    GameService game,
  ) {
    final currentBidder = state.currentBid['bidder']?.toString();
    final currentBidderName = currentBidder == null
        ? null
        : state.players
              .where((p) => p.id == currentBidder)
              .map((p) => p.name)
              .firstOrNull;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel, size: 16, color: Color(0xFF1565C0)),
              const SizedBox(width: 6),
              Expanded(
                child: currentBidderName == null
                    ? Text(
                        L10n.of(context).mtBidInProgress,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF5A4038),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              L10n.of(context).mtCurrentBidPoints(
                                state.currentBid['points'].toString(),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF5A4038),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          SuitIcon(
                            suit:
                                state.currentBid['suit']?.toString() ?? '',
                            size: 13,
                            color: _bidAccentColor(
                              state.currentBid['suit']?.toString(),
                            ),
                          ),
                        ],
                      ),
              ),
              if (_remainingSeconds > 0)
                Text(
                  '${_remainingSeconds}s',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _remainingSeconds <= 5
                        ? const Color(0xFFE53935)
                        : const Color(0xFF8A7A72),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildCompactBidControls(state, game),
        ],
      ),
    );
  }

  Widget _buildCompactBidControls(MightyGameStateData state, GameService game) {
    if (!state.isMyTurn) {
      final waitingName =
          state.players
              .where((p) => p.id == state.currentPlayer)
              .map((p) => p.name)
              .firstOrNull ??
          '...';
      return Text(
        L10n.of(context).mtWaitingFor(waitingName),
        style: const TextStyle(fontSize: 12, color: Color(0xFF8A7A72)),
      );
    }

    final currentBidPoints = (state.currentBid['points'] as num?)?.toInt() ?? 0;
    final currentBidSuit = state.currentBid['suit'] as String?;
    final modeMin = state.mode == '6p' ? 14 : 13;
    final canBidSamePoints =
        currentBidSuit != null &&
        currentBidSuit != 'no_trump' &&
        _bidSuit == 'no_trump';
    final minBid = canBidSamePoints
        ? currentBidPoints.clamp(modeMin, 20)
        : (currentBidPoints + 1).clamp(modeMin, 20);
    if (_bidPoints < minBid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _bidPoints = minBid);
      });
    }

    int minBidFor(String suit) {
      if (currentBidPoints == 0) return modeMin;
      final raw =
          (suit == 'no_trump' &&
              currentBidSuit != null &&
              currentBidSuit != 'no_trump')
          ? currentBidPoints
          : currentBidPoints + 1;
      return raw < modeMin ? modeMin : raw;
    }

    bool suitAvailable(String suit) => minBidFor(suit) <= 20;

    void selectSuit(String suit) {
      final needed = minBidFor(suit);
      if (needed > 20) return;
      setState(() {
        if (suit == 'no_trump') {
          _bidPoints = needed;
        } else if (_bidPoints < needed) {
          _bidPoints = needed;
        }
        _bidSuit = suit;
      });
    }

    final isTrueCeiling =
        currentBidPoints >= 20 && currentBidSuit == 'no_trump';
    final canTieWithNT =
        currentBidPoints >= 20 &&
        currentBidSuit != null &&
        currentBidSuit != 'no_trump' &&
        _bidSuit == 'no_trump';
    final canBid = !isTrueCeiling && (currentBidPoints < 20 || canTieWithNT);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              L10n.of(context).mtPoints,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5A4038),
              ),
            ),
            if (minBid >= 20)
              const Spacer()
            else
              Expanded(
                child: Slider(
                  value: _bidPoints.toDouble().clamp(minBid.toDouble(), 20),
                  min: minBid.toDouble(),
                  max: 20,
                  divisions: 20 - minBid,
                  label: '${_bidPoints.clamp(minBid, 20)}',
                  onChanged: (v) => setState(() => _bidPoints = v.toInt()),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _bidAccentColor(_bidSuit).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_bidPoints.clamp(minBid, 20)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: _bidAccentColor(_bidSuit),
                ),
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
            _buildSuitChip(
              'spade',
              '\u2660',
              const Color(0xFF2B2B2B),
              enabled: suitAvailable('spade'),
              onTap: () => selectSuit('spade'),
            ),
            _buildSuitChip(
              'heart',
              '\u2665',
              const Color(0xFFD24B4B),
              enabled: suitAvailable('heart'),
              onTap: () => selectSuit('heart'),
            ),
            _buildSuitChip(
              'diamond',
              '\u2666',
              const Color(0xFF6FB6E5),
              enabled: suitAvailable('diamond'),
              onTap: () => selectSuit('diamond'),
            ),
            _buildSuitChip(
              'club',
              '\u2663',
              const Color(0xFF4BAA6A),
              enabled: suitAvailable('club'),
              onTap: () => selectSuit('club'),
            ),
            _buildSuitChip(
              'no_trump',
              'NT',
              const Color(0xFF7B1FA2),
              enabled: suitAvailable('no_trump'),
              onTap: () => selectSuit('no_trump'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: canBid
                  ? () => game.mightySubmitBid(_bidPoints, _bidSuit)
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: _bidAccentColor(_bidSuit),
                disabledBackgroundColor: const Color(0xFFBDBDBD),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(L10n.of(context).mtBidPoints(_bidPoints)),
                  const SizedBox(width: 5),
                  SuitIcon(
                    suit: _bidSuit,
                    size: 14,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
            OutlinedButton(
              onPressed: () => game.mightyPass(),
              child: Text(L10n.of(context).mtPass),
            ),
            if (state.canDeclareDealMiss)
              OutlinedButton(
                onPressed: () => _confirmDealMiss(game),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD84315),
                  side: const BorderSide(color: Color(0xFFFF7043)),
                ),
                child: Text(L10n.of(context).mtDealMiss),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCompactKillPanel(MightyGameStateData state, GameService game) {
    final l10n = L10n.of(context);
    final ownHand = state.myCards.toSet();
    const suits = ['spade', 'heart', 'diamond', 'club'];
    const ranks = [
      'A',
      'K',
      'Q',
      'J',
      '10',
      '9',
      '8',
      '7',
      '6',
      '5',
      '4',
      '3',
      '2',
    ];

    if (!state.isMyTurn) {
      final declarerName =
          state.players
              .where((p) => p.id == state.declarer)
              .map((p) => p.name)
              .firstOrNull ??
          '...';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Text(
          l10n.mtKillPhaseWait(declarerName),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF5A4038),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.gps_fixed, size: 16, color: Color(0xFFD84315)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.mtKillPhasePrompt,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFD84315),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildKillCardChip(ownHand, 'mighty_joker'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final suit in suits) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _killSuitTab = suit),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: _killSuitTab == suit
                            ? (PlayingCard.suitColors[suit] ??
                                      const Color(0xFF5A4038))
                                  .withValues(alpha: 0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _killSuitTab == suit
                              ? (PlayingCard.suitColors[suit] ??
                                    const Color(0xFF5A4038))
                              : const Color(0xFFE0D8D4),
                          width: _killSuitTab == suit ? 2 : 1,
                        ),
                      ),
                      child: Center(child: SuitIcon(suit: suit, size: 20)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final rank in ranks)
                _buildKillCardChip(ownHand, 'mighty_${_killSuitTab}_$rank'),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _selectedKillCard == null
                ? null
                : () {
                    game.mightyDeclareKill(_selectedKillCard!);
                    setState(() => _selectedKillCard = null);
                  },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD84315),
              disabledBackgroundColor: const Color(0xFFBDBDBD),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(l10n.mtKillConfirm),
          ),
        ],
      ),
    );
  }

  Widget _buildHandRows(
    List<String> cards, {
    required Set<String> legalCards,
    required bool isPlaying,
    required bool isKitty,
    MightyGameStateData? state,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 24;
        final perRow = cards.length <= 7
            ? cards.length
            : (cards.length / 2).ceil();
        final cardPadding = cards.length >= 8 ? 1.5 : 3.0;
        final totalPadding = perRow * cardPadding * 2;
        final cardWidth = ((availableWidth - totalPadding) / perRow).clamp(
          0.0,
          52.0,
        );
        final cardHeight = (cardWidth * 1.4).clamp(52.0, 73.0);

        Widget buildCard(String cardId) {
          final isLegal =
              !isPlaying || legalCards.isEmpty || legalCards.contains(cardId);
          // Kitty: block mighty, joker, and friend card from discard
          final isKittyBlocked = isKitty && _isKittyBlockedCard(cardId, state);
          final isSelected = isPlaying
              ? _selectedCard == cardId
              : isKitty
              ? _discardSelection.contains(cardId)
              : false;

          // Trump / mighty / joker-call previews. After bidding these come
          // straight from state; during bidding we derive them from the
          // current top bid's suit so the hand updates live.
          //   mighty     : trump=='spade' → ♦A, else → ♠A
          //   jokerCall  : trump=='club'  → ♠3, else → ♣3 (default; once
          //                bidding finishes, server-published value wins)
          String? effectiveTrump = state?.trumpSuit;
          String? effectiveMighty = state?.mightyCard;
          String? effectiveJokerCall = state?.jokerCallCard;
          if (state != null && state.phase == 'bidding') {
            final bidSuit = state.currentBid['suit'];
            if (bidSuit is String && bidSuit.isNotEmpty) {
              effectiveTrump = bidSuit;
              effectiveMighty = bidSuit == 'spade'
                  ? 'mighty_diamond_A'
                  : 'mighty_spade_A';
              // Joker-call only fires in suited bidding — skip the preview
              // in NT so the badge doesn't suggest a power that won't apply.
              effectiveJokerCall = bidSuit == 'no_trump'
                  ? null
                  : (bidSuit == 'club' ? 'mighty_spade_3' : 'mighty_club_3');
            }
          }

          // Badge: mighty card, joker call card, friend card, or kitty card
          final isMightyCard =
              effectiveMighty != null && cardId == effectiveMighty;
          final isJokerCallCard =
              !isMightyCard &&
              effectiveJokerCall != null &&
              cardId == effectiveJokerCall;
          final isFriendCard =
              !isMightyCard &&
              !isJokerCallCard &&
              state?.friendCard != null &&
              cardId == state!.friendCard;
          final isKittyCard =
              !isMightyCard &&
              !isJokerCallCard &&
              !isFriendCard &&
              isKitty &&
              (state?.kittyCards.contains(cardId) ?? false);
          // Post-kill/suicide: cards received via redistribution get the move_up badge
          // for the receiving player (similar to declarer's kitty-pickup highlight).
          final isRedistCard =
              !isMightyCard &&
              !isJokerCallCard &&
              !isFriendCard &&
              !isKittyCard &&
              (state?.newlyReceivedCards.contains(cardId) ?? false);
          // Trump suit border.
          Color? trumpBorder;
          if (effectiveTrump != null && effectiveTrump != 'no_trump') {
            final cardSuit = _getCardSuit(cardId);
            if (cardSuit == effectiveTrump) {
              trumpBorder = PlayingCard.suitColors[cardSuit];
            }
          }

          return GestureDetector(
            onTap: () {
              setState(() {
                if (isPlaying) {
                  if (!isLegal) return;
                  _selectedCard = _selectedCard == cardId ? null : cardId;
                  // Joker suit is not pre-selected — the player must choose
                  // explicitly before they are allowed to lead the joker.
                  if (_selectedCard == 'mighty_joker') {
                    _jokerSuitChoice = null;
                  }
                } else if (isKitty) {
                  if (isKittyBlocked) return;
                  if (_discardSelection.contains(cardId)) {
                    _discardSelection.remove(cardId);
                  } else if (_discardSelection.length < 3) {
                    _discardSelection.add(cardId);
                  }
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(0, isSelected ? -12 : 0, 0),
              child: Opacity(
                opacity: (isLegal && !isKittyBlocked) ? 1.0 : 0.4,
                child: Container(
                  decoration: isSelected
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF355D89,
                              ).withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        )
                      : null,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: cardPadding),
                    child: PlayingCard(
                      cardId: _displayCardId(cardId),
                      width: cardWidth,
                      height: cardHeight,
                      isSelected: isSelected,
                      isInteractive: false,
                      badgeIcon: isMightyCard
                          ? Icons.star
                          : isJokerCallCard
                          ? Icons.gps_fixed
                          : isFriendCard
                          ? Icons.people
                          : isKittyCard
                          ? Icons.move_up
                          : isRedistCard
                          ? Icons.move_up
                          : null,
                      badgeColor: isMightyCard
                          ? const Color(0xFFFFB300)
                          : isJokerCallCard
                          ? const Color(0xFFE53935)
                          : isFriendCard
                          ? const Color(0xFF4CAF50)
                          : isKittyCard
                          ? const Color(0xFF7B1FA2)
                          : isRedistCard
                          ? const Color(0xFF7B1FA2)
                          : null,
                      borderColor: trumpBorder,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        if (cards.length <= 7) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: cards.map(buildCard).toList(),
            ),
          );
        }

        final half = (cards.length / 2).ceil();
        final firstRow = cards.take(half).toList();
        final secondRow = cards.skip(half).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: firstRow.map(buildCard).toList(),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: secondRow.map(buildCard).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildJokerSuitSelector() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            L10n.of(context).mtJokerSuit,
            style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
          ),
          ...[
            ('spade', '\u2660', const Color(0xFF2B2B2B)),
            ('heart', '\u2665', const Color(0xFFD24B4B)),
            ('diamond', '\u2666', const Color(0xFF6FB6E5)),
            ('club', '\u2663', const Color(0xFF4BAA6A)),
          ].map((s) {
            final selected = _jokerSuitChoice == s.$1;
            return GestureDetector(
              onTap: () => setState(() => _jokerSuitChoice = s.$1),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? s.$3.withValues(alpha: 0.12)
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? s.$3 : const Color(0xFFE0D8D4),
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Text(s.$2, style: TextStyle(fontSize: 16, color: s.$3)),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Round End (SK-style) ──
  Widget _buildRoundEndUI(MightyGameStateData state) {
    final result = state.roundResult;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F1EC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7DBD4)),
            ),
            child: Text(
              L10n.of(context).mtRoundResult(state.round),
              style: const TextStyle(
                color: Color(0xFF5A4038),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (result != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: result['success'] == true
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                result['success'] == true
                    ? L10n.of(context).mtDeclarerWins(result['declarerPoints'])
                    : L10n.of(
                        context,
                      ).mtDeclarerFails(result['declarerPoints']),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: result['success'] == true
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFE53935),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Divider(height: 8),
          ...state.players.map((p) {
            final roundScore = (result?['scores']?[p.id] as num?)?.toInt();
            final totalScore = state.scores[p.id] ?? 0;
            final isDeclarer = p.id == state.declarer;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: p.position == 'self'
                    ? const Color(0xFFF7F1EC)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (isDeclarer)
                    const Text(
                      '\u2605 ',
                      style: TextStyle(fontSize: 12, color: Color(0xFFFF8A00)),
                    ),
                  Expanded(
                    child: Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: p.position == 'self'
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: const Color(0xFF5A4038),
                      ),
                    ),
                  ),
                  if (roundScore != null)
                    Text(
                      '${roundScore > 0 ? '+' : ''}$roundScore',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: roundScore > 0
                            ? const Color(0xFF4CAF50)
                            : roundScore < 0
                            ? const Color(0xFFE53935)
                            : const Color(0xFF5A4038),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Text(
                    '$totalScore',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF5A4038),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Text(
            L10n.of(context).mtNextRound,
            style: const TextStyle(color: Color(0xFF8A7A72), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Game End (SK-style) ──
  Widget _buildGameEndUI(MightyGameStateData state, GameService game) {
    final sorted = List<MightyPlayer>.from(state.players)
      ..sort(
        (a, b) => (state.scores[b.id] ?? 0).compareTo(state.scores[a.id] ?? 0),
      );

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F1EC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE7DBD4)),
            ),
            child: Text(
              L10n.of(context).mtGameOver,
              style: const TextStyle(
                color: Color(0xFF5A4038),
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 16),
          ...sorted.asMap().entries.map((entry) {
            final rank = entry.key + 1;
            final p = entry.value;
            final score = state.scores[p.id] ?? 0;
            final isWinner = rank == 1;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isWinner
                    ? const Color(0xFFFFF8E1)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: isWinner
                    ? Border.all(color: const Color(0xFFFFD700))
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isWinner
                          ? const Color(0xFFFFD700)
                          : const Color(0xFFF5F5F5),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isWinner
                            ? const Color(0xFFFFB300)
                            : const Color(0xFFE0D8D4),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          color: isWinner
                              ? Colors.black
                              : const Color(0xFF5A4038),
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.name,
                      style: TextStyle(
                        color: const Color(0xFF5A4038),
                        fontSize: isWinner ? 16 : 14,
                        fontWeight: isWinner
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  Text(
                    '$score',
                    style: TextStyle(
                      color: const Color(0xFF5A4038),
                      fontSize: isWinner ? 18 : 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFC7DCF8)),
            ),
            child: Text(
              _gameEndCountdown > 0
                  ? L10n.of(context).mtReturningIn(_gameEndCountdown)
                  : L10n.of(context).mtReturningToRoom,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF355D89),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Card View Request Popup ──
  Widget _buildCardViewRequestPopup(GameService game) {
    final request = game.firstIncomingCardViewRequest;
    if (request == null) return const SizedBox.shrink();
    final spectatorNickname =
        request['spectatorNickname'] ?? L10n.of(context).gameSpectator;
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
              color: Colors.black.withValues(alpha: 0.2),
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
                    L10n.of(context).gameCardViewRequest(spectatorNickname),
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
                    onPressed: () =>
                        game.respondCardViewRequest(spectatorId, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFCC6666),
                      side: const BorderSide(color: Color(0xFFCC6666)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(L10n.of(context).gameReject),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        game.respondCardViewRequest(spectatorId, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6A9BD1),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(L10n.of(context).gameAllow),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => game.rejectAllCardViewRequests(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF999999),
                      side: const BorderSide(color: Color(0xFFCCCCCC)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      L10n.of(context).gameAlwaysReject,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      game.respondCardViewRequest(spectatorId, true);
                      game.setAutoAcceptCardView(true);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF4CAF50),
                      side: const BorderSide(color: Color(0xFF4CAF50)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: Text(
                      L10n.of(context).gameAlwaysAllow,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Error Banner ──
  Widget _buildTimeoutResetChip(GameService game) {
    return GestureDetector(
      onTap: () => game.resetTimeout(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFB74D)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timer_off_outlined,
              size: 15,
              color: Color(0xFFE65100),
            ),
            const SizedBox(width: 5),
            Text(
              '${game.myTimeoutCount}/3',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE65100),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              L10n.of(context).gameReset,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFE65100),
                fontWeight: FontWeight.w700,
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
        ),
        child: Row(
          children: [
            const Icon(Icons.timer_off, color: Color(0xFFE65100)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                L10n.of(context).gameTimeout(playerName),
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

  Widget _buildDealMissRevealOverlay(MightyDealMissEvent event) {
    final l10n = L10n.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() {
          _dismissedDealMissKey = '${event.round}-${event.playerId}';
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F2),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFFFAB91), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 12,
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
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: Color(0xFFD84315),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.mtDealMiss,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Color(0xFFD84315),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.mtDealMissReveal(
                    event.playerName,
                    _formatHandScore(event.handScore),
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4038),
                  ),
                ),
                const SizedBox(height: 10),
                _buildDealMissCardRows(event.cards),
                const SizedBox(height: 10),
                Text(
                  l10n.mtDealMissTapToClose,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A7A72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatHandScore(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  /// Full-screen overlay shown to everyone when a player successfully
  /// declares 세팅. Reveals the declarer's hand + who they are + a close
  /// prompt. Dismissed by tapping; keyed on round+playerId so a later
  /// round's reveal re-shows even if the prior key matches.
  Widget _buildSettingRevealOverlay(MightySettingEvent event) {
    final l10n = L10n.of(context);
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() {
          _dismissedSettingKey = '${event.round}-${event.playerId}';
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFDE7),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFB300), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.emoji_events,
                      size: 22,
                      color: Color(0xFFE65100),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.mtSettingRevealTitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.mtSettingRevealBody(event.playerName),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4038),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDealMissCardRows(event.cards, splitAt: 6),
                const SizedBox(height: 10),
                Text(
                  l10n.mtSettingTapToClose,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A7A72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContractChangeBanner(_ContractChangeInfo info) {
    final l10n = L10n.of(context);
    Widget suitChip(String suit) {
      if (suit == 'no_trump') {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF3E5F5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'NT',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF7B1FA2),
            ),
          ),
        );
      }
      final color = PlayingCard.suitColors[suit] ?? const Color(0xFF5A4038);
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: SuitIcon(suit: suit, size: 16, color: color),
      );
    }

    final rows = <Widget>[];
    if (info.oldTrump != null && info.newTrump != null) {
      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.mtChangeTrump,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4E342E),
              ),
            ),
            const SizedBox(width: 8),
            suitChip(info.oldTrump!),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: Color(0xFF8D6E63),
            ),
            const SizedBox(width: 6),
            suitChip(info.newTrump!),
          ],
        ),
      );
    }
    if (info.oldBid != null && info.newBid != null) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
      rows.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.trending_up_rounded,
              size: 16,
              color: Color(0xFFC62828),
            ),
            const SizedBox(width: 6),
            Text(
              '${info.oldBid}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A7A72),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 16,
              color: Color(0xFF8D6E63),
            ),
            const SizedBox(width: 6),
            Text(
              '${info.newBid}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFFC62828),
              ),
            ),
          ],
        ),
      );
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    return Positioned(
      top: 68,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFB74D), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: rows),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingButton(GameService game) {
    return GestureDetector(
      onTap: () => _confirmSetting(game),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFFFB74D)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events, size: 13, color: Color(0xFFE65100)),
            const SizedBox(width: 5),
            Text(
              L10n.of(context).mtSetting,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFFE65100),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmSetting(GameService game) async {
    final l10n = L10n.of(context);
    final ok = await _confirmBidAction(
      title: l10n.mtSettingConfirmTitle,
      body: Text(l10n.mtSettingConfirmBody),
    );
    if (ok) game.mightyDeclareSetting();
  }

  Widget _buildPrevTrickButton(MightyGameStateData state) {
    return GestureDetector(
      onTap: () => _showPrevTrickDialog(state),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EAF6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF9FA8DA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 13, color: Color(0xFF3F51B5)),
            const SizedBox(width: 5),
            Text(
              L10n.of(context).mtPrevTrick,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3F51B5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPrevTrickDialog(MightyGameStateData state) async {
    if (state.tricks.isEmpty) return;
    final prev = state.tricks.last;
    final l10n = L10n.of(context);
    final winnerName = state.players
        .firstWhere(
          (p) => p.id == prev.winner,
          orElse: () => MightyPlayer(id: prev.winner, name: prev.winner),
        )
        .name;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: const Color(0xFFFFF8F2),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.history, size: 18, color: Color(0xFF3F51B5)),
                  const SizedBox(width: 6),
                  Text(
                    l10n.mtPrevTrickTitle(state.tricks.length),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3F51B5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (int i = 0; i < prev.cards.length; i++) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: prev.cards[i].playerId == prev.winner
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFFFB74D),
                                    width: 2,
                                  ),
                                )
                              : null,
                          padding: const EdgeInsets.all(1),
                          child: PlayingCard(
                            cardId: _displayCardId(prev.cards[i].cardId),
                            width: 42,
                            height: 59,
                            isInteractive: false,
                          ),
                        ),
                        const SizedBox(height: 2),
                        SizedBox(
                          width: 46,
                          child: Text(
                            state.players
                                .firstWhere(
                                  (p) => p.id == prev.cards[i].playerId,
                                  orElse: () => MightyPlayer(
                                    id: prev.cards[i].playerId,
                                    name: prev.cards[i].playerId,
                                  ),
                                )
                                .name,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: prev.cards[i].playerId == prev.winner
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: prev.cards[i].playerId == prev.winner
                                  ? const Color(0xFFE65100)
                                  : const Color(0xFF5A4038),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text(
                l10n.mtPrevTrickWinner(winnerName),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF5A4038),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE6F1FF),
                    foregroundColor: const Color(0xFF355D89),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    l10n.commonClose,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Render a small hand-preview. When [splitAt] is null or below the hand
  /// size, cards are laid out on a single row; otherwise they're split into
  /// two equal(ish) rows. Deal-miss always splits (full hand ≥ 8 cards is
  /// awkward in one row), while the setting reveal only splits past the
  /// ≥ 5-card threshold.
  Widget _buildDealMissCardRows(List<String> cards, {int? splitAt = 1}) {
    Widget buildRow(List<String> ids) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < ids.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            PlayingCard(
              cardId: _displayCardId(ids[i]),
              width: 38,
              height: 54,
              isInteractive: false,
            ),
          ],
        ],
      );
    }

    if (splitAt == null || cards.length < splitAt) {
      return buildRow(cards);
    }
    final splitIndex = (cards.length / 2).ceil();
    final row1 = cards.take(splitIndex).toList();
    final row2 = cards.skip(splitIndex).toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildRow(row1),
        if (row2.isNotEmpty) ...[const SizedBox(height: 4), buildRow(row2)],
      ],
    );
  }

  Widget _buildKillCardChip(Set<String> ownHand, String cardId) {
    final inHand = ownHand.contains(cardId);
    final isSelected = _selectedKillCard == cardId;
    final isJoker = cardId == 'mighty_joker';

    String? rank;
    String? suit;
    Color textColor;
    if (isJoker) {
      textColor = const Color(0xFF7B1FA2);
    } else {
      final parts = cardId.replaceFirst('mighty_', '').split('_');
      suit = parts[0];
      rank = parts[1];
      textColor = PlayingCard.suitColors[suit] ?? const Color(0xFF1A1A1A);
    }

    return GestureDetector(
      onTap: inHand ? null : () => setState(() => _selectedKillCard = cardId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: isJoker ? double.infinity : 52,
        padding: EdgeInsets.symmetric(
          horizontal: isJoker ? 12 : 4,
          vertical: isJoker ? 12 : 8,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: inHand
              ? const Color(0xFFECEFF1)
              : isSelected
              ? const Color(0xFFFFEBEE)
              : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFD84315)
                : const Color(0xFFE0D8D4),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: isJoker
            ? Text(
                'JOKER',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: inHand ? const Color(0xFFBDBDBD) : textColor,
                  decoration: inHand
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  letterSpacing: 1.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SuitIcon(
                    suit: suit!,
                    size: 14,
                    color: inHand ? const Color(0xFFBDBDBD) : textColor,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    rank!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: inHand ? const Color(0xFFBDBDBD) : textColor,
                      decoration: inHand
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildKillRevealOverlay(
    MightyGameStateData state,
    MightyKillEvent event,
  ) {
    final l10n = L10n.of(context);
    String? targetSuit;
    String cardLabel;
    if (event.targetCardId == 'mighty_joker') {
      cardLabel = 'JOKER';
    } else {
      final parts = event.targetCardId.replaceFirst('mighty_', '').split('_');
      targetSuit = parts.length > 1 ? parts[0] : null;
      cardLabel = parts.length > 1 ? parts[1] : event.targetCardId;
    }
    // Build the kill-result body as inline runs so the suit symbol can render
    // as a SuitIcon (consistent on Android) instead of a Unicode glyph.
    const cardSentinel = 'CARD';
    final body = event.wasKitty
        ? l10n.mtKillResultSuicide(event.declarerName, cardSentinel)
        : l10n.mtKillResultKilled(
            event.declarerName,
            cardSentinel,
            event.victimName ?? '?',
          );
    final bodyParts = body.split(cardSentinel);
    const bodyStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: Color(0xFF5A4038),
    );
    final bodyWidget = targetSuit == null
        ? Text(
            body.replaceAll(cardSentinel, cardLabel),
            textAlign: TextAlign.center,
            style: bodyStyle,
          )
        : RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: bodyStyle,
              children: [
                if (bodyParts.isNotEmpty) TextSpan(text: bodyParts[0]),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: SuitIcon(
                    suit: targetSuit,
                    size: 14,
                    color: _bidAccentColor(targetSuit),
                  ),
                ),
                TextSpan(text: cardLabel),
                if (bodyParts.length > 1) TextSpan(text: bodyParts[1]),
              ],
            ),
          );
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() {
          _dismissedKillKey = '${state.round}-${event.targetCardId}';
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFF7043), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.gps_fixed,
                      size: 22,
                      color: Color(0xFFD84315),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.mtKillPhase,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        color: Color(0xFFD84315),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                bodyWidget,
                const SizedBox(height: 10),
                Text(
                  l10n.mtDealMissTapToClose,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF8A7A72),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Positioned(
      top: 60,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFEBEE),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE53935)),
        ),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFFE53935),
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // ── Helpers ──
  String _phaseLabel(String phase) {
    final l10n = L10n.of(context);
    switch (phase) {
      case 'bidding':
        return l10n.mtPhaseBidding;
      case 'kill_select':
        return l10n.mtKillPhase;
      case 'kitty_exchange':
        return l10n.mtPhaseKitty;
      case 'playing':
        return l10n.mtPhasePlaying;
      case 'trick_end':
        return l10n.mtPhasePlaying;
      case 'round_end':
        return l10n.mtPhaseRoundEnd;
      case 'game_end':
        return l10n.mtPhaseGameEnd;
      default:
        return phase;
    }
  }

  String? _getCardSuit(String cardId) {
    if (cardId == 'mighty_joker') return null;
    final stripped = cardId.replaceFirst('mighty_', '');
    final parts = stripped.split('_');
    if (parts.length >= 2) return parts[0];
    return null;
  }

  /// Client-side mirror of the server's trick-play legality so users can
  /// pre-select a card while waiting for their turn. Honours the "must
  /// follow lead suit when possible" rule; mighty and joker are always
  /// playable. Joker-call-forced-joker corner case is deliberately skipped
  /// — the server will still validate the actual play.
  Set<String> _previewLegalCards(MightyGameStateData state) {
    final hand = state.myCards;
    final trick = state.currentTrick;
    if (hand.isEmpty) return <String>{};
    if (trick.isEmpty) return hand.toSet();

    final leadCardId = trick[0].cardId;
    final leadSuit = leadCardId == 'mighty_joker'
        ? (state.jokerSuitDeclared)
        : _getCardSuit(leadCardId);
    if (leadSuit == null) return hand.toSet();

    final suitCards = hand.where((c) {
      if (c == 'mighty_joker') return false;
      return _getCardSuit(c) == leadSuit;
    }).toList();

    if (suitCards.isEmpty) return hand.toSet();
    // Must follow suit; mighty and joker can always be substituted.
    final legal = <String>{...suitCards};
    if (hand.contains('mighty_joker')) legal.add('mighty_joker');
    final mighty = state.mightyCard;
    if (mighty != null && hand.contains(mighty)) legal.add(mighty);
    return legal;
  }

  bool _isKittyBlockedCard(String cardId, MightyGameStateData? state) {
    if (state == null) return false;
    // Block mighty card
    if (state.mightyCard != null && cardId == state.mightyCard) return true;
    // Block joker
    if (cardId == 'mighty_joker') return true;
    // Block friend card (unless it's a special value)
    if (_friendCardSelection.isNotEmpty &&
        _friendCardSelection != 'no_friend' &&
        _friendCardSelection != 'first_trick' &&
        cardId == _friendCardSelection) {
      return true;
    }
    return false;
  }

  Widget _buildJokerCallToggle() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            L10n.of(context).mtJokerCall,
            style: const TextStyle(fontSize: 12, color: Color(0xFF5A4038)),
          ),
          GestureDetector(
            onTap: () => setState(() => _jokerCallChoice = true),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _jokerCallChoice
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _jokerCallChoice
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFE0D8D4),
                  width: _jokerCallChoice ? 2 : 1,
                ),
              ),
              child: Text(
                L10n.of(context).mtYes,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: _jokerCallChoice
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: _jokerCallChoice
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF5A4038),
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _jokerCallChoice = false),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: !_jokerCallChoice
                    ? const Color(0xFFFFEBEE)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: !_jokerCallChoice
                      ? const Color(0xFFE53935)
                      : const Color(0xFFE0D8D4),
                  width: !_jokerCallChoice ? 2 : 1,
                ),
              ),
              child: Text(
                L10n.of(context).mtNo,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: !_jokerCallChoice
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: !_jokerCallChoice
                      ? const Color(0xFFE53935)
                      : const Color(0xFF5A4038),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSpectatorListDialog(GameService game) {
    final spectators = game.spectators;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.people_alt, color: Color(0xFF5A4038)),
            const SizedBox(width: 8),
            Text(L10n.of(context).gameSpectatorList),
          ],
        ),
        content: spectators.isEmpty
            ? SizedBox(
                height: 60,
                child: Center(
                  child: Text(
                    L10n.of(context).gameNoSpectators,
                    style: const TextStyle(color: Color(0xFF9A8E8A)),
                  ),
                ),
              )
            : SizedBox(
                width: double.maxFinite,
                height: 220,
                child: ListView.separated(
                  itemCount: spectators.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final nickname = spectators[index]['nickname'] ?? '';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F1F1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE0D8D4)),
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
          if (!game.isSpectator)
            StatefulBuilder(
              builder: (context, setDialogState) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        game.setAutoAcceptCardView(!game.autoAcceptCardView);
                        setDialogState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: game.autoAcceptCardView
                              ? const Color(0xFFE8F5E9)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              game.autoAcceptCardView
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                              size: 16,
                              color: game.autoAcceptCardView
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFF999999),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              L10n.of(context).gameAlwaysAllow,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: game.autoAcceptCardView
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFF999999),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        game.setAutoRejectCardView(!game.autoRejectCardView);
                        setDialogState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: game.autoRejectCardView
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              game.autoRejectCardView
                                  ? Icons.block
                                  : Icons.block_outlined,
                              size: 16,
                              color: game.autoRejectCardView
                                  ? const Color(0xFFE53935)
                                  : const Color(0xFF999999),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              L10n.of(context).gameAlwaysReject,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: game.autoRejectCardView
                                    ? const Color(0xFFE53935)
                                    : const Color(0xFF999999),
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
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).gameClose),
          ),
        ],
      ),
    );
  }

  void _showScoreHistoryDialog(MightyGameStateData state, GameService game) {
    final suitSymbol = {
      'spade': '♠',
      'heart': '♥',
      'diamond': '♦',
      'club': '♣',
      'no_trump': 'NT',
    };

    final cumulativeScores = <String, int>{
      for (final p in state.players) p.id: 0,
    };

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFFFBFCFE),
        titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
        contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.table_chart_rounded,
                      size: 16,
                      color: Color(0xFF295EA8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    L10n.of(context).mtScoreHistory,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF233142),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFC9DCF7)),
                    ),
                    child: Text(
                      '/${game.roomTargetScore}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF295EA8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${state.scoreHistory.length}R',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7A90),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: LayoutBuilder(
              builder: (context, constraints) {
                Widget cell(
                  String text, {
                  TextAlign align = TextAlign.center,
                  FontWeight fontWeight = FontWeight.w600,
                  Color color = const Color(0xFF5A4038),
                  double fontSize = 10,
                  EdgeInsets padding = const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 8,
                  ),
                }) {
                  return Padding(
                    padding: padding,
                    child: Text(
                      text,
                      textAlign: align,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: fontWeight,
                        color: color,
                      ),
                    ),
                  );
                }

                // Bid cell renders the trump as a SuitIcon (Android-safe)
                // alongside the bid value + success/fail mark.
                Widget bidCell({
                  required String? trumpSuit,
                  required String label,
                  Color color = const Color(0xFF233142),
                  bool dealMiss = false,
                }) {
                  if (dealMiss || trumpSuit == null) {
                    return cell(
                      label,
                      align: TextAlign.left,
                      fontWeight: FontWeight.w700,
                      color: color,
                    );
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SuitIcon(
                          suit: trumpSuit,
                          size: 10,
                          color: _bidAccentColor(trumpSuit),
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final border = TableBorder.symmetric(
                  inside: const BorderSide(
                    color: Color(0xFFDCE4EE),
                    width: 0.6,
                  ),
                  outside: const BorderSide(
                    color: Color(0xFFDCE4EE),
                    width: 0.8,
                  ),
                );

                return Table(
                  columnWidths: {
                    0: const FlexColumnWidth(0.7),
                    1: const FlexColumnWidth(1.5),
                    for (int i = 0; i < state.players.length; i++)
                      i + 2: const FlexColumnWidth(1),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  border: border,
                  children: [
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFEAF2FF)),
                      children: [
                        cell(
                          'R',
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          color: const Color(0xFF295EA8),
                        ),
                        cell(
                          L10n.of(context).mtBidShort,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          color: const Color(0xFF295EA8),
                        ),
                        ...state.players.map(
                          (p) => cell(
                            p.name.length > 2 ? p.name.substring(0, 2) : p.name,
                            fontWeight: FontWeight.w800,
                            fontSize: 9.5,
                            color: const Color(0xFF295EA8),
                          ),
                        ),
                      ],
                    ),
                    ...state.scoreHistory.map((entry) {
                      final trump =
                          suitSymbol[entry.trumpSuit] ?? entry.trumpSuit ?? '?';
                      for (final p in state.players) {
                        cumulativeScores[p.id] =
                            (cumulativeScores[p.id] ?? 0) +
                            (entry.scores[p.id] ?? 0);
                      }
                      final rowTint = entry.dealMiss
                          ? const Color(0xFFFFF4E5)
                          : (entry.success
                                ? const Color(0xFFF4FBF6)
                                : const Color(0xFFFFF6F7));
                      final dealMissLabel = L10n.of(context).mtDealMiss;
                      // For NT contracts, fall back to "NT" inline (no suit
                      // glyph). Other contracts render the suit via SuitIcon.
                      final trumpKey = entry.trumpSuit;
                      final showSuitIcon =
                          trumpKey != null && trumpKey != 'no_trump';
                      final bidLabel = entry.dealMiss
                          ? dealMissLabel
                          : showSuitIcon
                          ? '${entry.bid}${entry.success ? '✓' : '✗'}'
                          : '$trump${entry.bid}${entry.success ? '✓' : '✗'}';
                      return TableRow(
                        decoration: BoxDecoration(color: rowTint),
                        children: [
                          cell('${entry.round}', fontWeight: FontWeight.w700),
                          bidCell(
                            trumpSuit: showSuitIcon ? trumpKey : null,
                            label: bidLabel,
                            color: entry.dealMiss
                                ? const Color(0xFFB56A1D)
                                : const Color(0xFF233142),
                            dealMiss: entry.dealMiss,
                          ),
                          ...state.players.map((p) {
                            final diff = entry.scores[p.id] ?? 0;
                            final isDeclTeam =
                                !entry.dealMiss &&
                                (p.id == entry.declarer ||
                                    p.id == entry.partner);
                            return cell(
                              diff == 0 ? '0' : (diff > 0 ? '+$diff' : '$diff'),
                              fontSize: 9.5,
                              fontWeight: isDeclTeam || diff != 0
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: diff > 0
                                  ? const Color(0xFF1F8B4C)
                                  : diff < 0
                                  ? const Color(0xFFD04A5B)
                                  : const Color(0xFF425466),
                            );
                          }),
                        ],
                      );
                    }),
                    TableRow(
                      decoration: const BoxDecoration(color: Color(0xFFF0F4F8)),
                      children: [
                        cell('', fontWeight: FontWeight.w800),
                        cell(
                          L10n.of(context).mtTotal,
                          align: TextAlign.left,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF233142),
                        ),
                        ...state.players.map((p) {
                          final total = cumulativeScores[p.id] ?? 0;
                          return cell(
                            '$total',
                            fontWeight: FontWeight.w800,
                            color: total >= 0
                                ? const Color(0xFF1F8B4C)
                                : const Color(0xFFD04A5B),
                          );
                        }),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(L10n.of(context).mtClose),
          ),
        ],
      ),
    );
  }

  // ── Player Profile Dialog ──
  void _showPlayerProfileDialog(
    String nickname,
    GameService game, {
    bool isBot = false,
  }) {
    game.requestProfile(nickname);
    showDialog(
      context: context,
      builder: (ctx) {
        return Consumer<GameService>(
          builder: (ctx, game, _) {
            final profile = game.profileFor(nickname);
            final isLoading =
                profile == null || profile['nickname'] != nickname;
            final isMe = nickname == game.playerName;
            final isBlockedUser = game.isBlocked(nickname);
            final l10n = L10n.of(context);

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              title: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8DDD8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.person_outline,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                nickname,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF3E312A),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                isMe
                                    ? l10n.gameMyProfile
                                    : l10n.gamePlayerProfile,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF84766E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (!isMe && !isBot) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (game.friends.contains(nickname))
                            _buildProfileIconBtn(
                              Icons.check,
                              const Color(0xFFBDBDBD),
                              l10n.gameAlreadyFriend,
                              () {},
                            )
                          else if (game.sentFriendRequests.contains(nickname))
                            _buildProfileIconBtn(
                              Icons.hourglass_top,
                              const Color(0xFFBDBDBD),
                              l10n.gameRequestPending,
                              () {},
                            )
                          else
                            _buildProfileIconBtn(
                              Icons.person_add,
                              const Color(0xFF81C784),
                              l10n.gameAddFriend,
                              () {
                                game.addFriendAction(nickname);
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(l10n.gameFriendRequestSent),
                                  ),
                                );
                              },
                            ),
                          _buildProfileIconBtn(
                            isBlockedUser ? Icons.block : Icons.shield_outlined,
                            isBlockedUser
                                ? const Color(0xFF64B5F6)
                                : const Color(0xFFFF8A65),
                            isBlockedUser ? l10n.gameUnblock : l10n.gameBlock,
                            () {
                              if (isBlockedUser) {
                                game.unblockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.gameUnblocked)),
                                );
                              } else {
                                game.blockUserAction(nickname);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(l10n.gameBlocked)),
                                );
                              }
                            },
                          ),
                          _buildProfileIconBtn(
                            Icons.flag,
                            const Color(0xFFE57373),
                            l10n.gameReport,
                            () {
                              Navigator.pop(ctx);
                              _showReportDialog(nickname, game);
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              content: isLoading
                  ? const SizedBox(
                      height: 140,
                      width: 360,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 420,
                        maxHeight: 560,
                      ),
                      child: SingleChildScrollView(
                        child: _buildProfileContent(profile),
                      ),
                    ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.gameClose),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildProfileIconBtn(
    IconData icon,
    Color color,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  Widget _buildProfileContent(Map<String, dynamic> data) {
    final profile = data['profile'] as Map<String, dynamic>?;
    if (profile == null) return Text(L10n.of(context).gameProfileNotFound);

    final l10n = L10n.of(context);
    final level = profile['level'] ?? 1;
    final expTotal = profile['expTotal'] ?? 0;
    final leaveCount = profile['leaveCount'] ?? 0;
    final reportCount = profile['reportCount'] ?? 0;
    final totalGames = profile['totalGames'] ?? 0;
    final bannerKey = profile['bannerKey']?.toString();

    // Mighty stats
    final mightyTotalGames = profile['mightyTotalGames'] ?? 0;
    final mightyWins = profile['mightyWins'] ?? 0;
    final mightyLosses = profile['mightyLosses'] ?? 0;
    final mightyWinRate = profile['mightyWinRate'] ?? 0;
    final mightySeasonRating = profile['mightySeasonRating'] ?? 1000;
    final mightySeasonGames = profile['mightySeasonGames'] ?? 0;
    final mightySeasonWins = profile['mightySeasonWins'] ?? 0;
    final mightySeasonLosses = profile['mightySeasonLosses'] ?? 0;
    final mightySeasonWinRate = profile['mightySeasonWinRate'] ?? 0;

    final recentMatches = (data['recentMatches'] as List<dynamic>? ?? [])
        .where((m) => m['gameType'] == 'mighty')
        .toList();
    final profileNickname = data['nickname']?.toString() ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildProfileHeader(level as int, expTotal as int, bannerKey),
        const SizedBox(height: 8),
        _buildMannerLeaveRow(
          totalGames: totalGames as int,
          reportCount: reportCount as int,
          leaveCount: leaveCount as int,
        ),
        const SizedBox(height: 10),
        _buildProfileSection(
          title: l10n.rankingMightySeasonRanked,
          accent: const Color(0xFF2E7D32),
          background: const Color(0xFFE8F5E9),
          icon: Icons.emoji_events,
          iconColor: const Color(0xFFFFD54F),
          mainText: '$mightySeasonRating',
          chips: [
            _buildStatChip(
              l10n.gameStatRecord,
              l10n.gameRecordFormat(
                mightySeasonGames as int,
                mightySeasonWins as int,
                mightySeasonLosses as int,
              ),
            ),
            _buildStatChip(l10n.gameStatWinRate, '$mightySeasonWinRate%'),
          ],
        ),
        const SizedBox(height: 10),
        _buildProfileSection(
          title: l10n.rankingMightyRecord,
          accent: const Color(0xFF1B5E20),
          background: const Color(0xFFF1F8E9),
          icon: Icons.military_tech,
          iconColor: const Color(0xFF4CAF50),
          mainText: '',
          chips: [
            _buildStatChip(
              l10n.gameStatRecord,
              l10n.gameRecordFormat(
                mightyTotalGames as int,
                mightyWins as int,
                mightyLosses as int,
              ),
            ),
            _buildStatChip(l10n.gameStatWinRate, '$mightyWinRate%'),
          ],
        ),
        const SizedBox(height: 12),
        _buildRecentMatchesList(recentMatches, profileNickname),
      ],
    );
  }

  Widget _buildProfileHeader(int level, int expTotal, String? bannerKey) {
    final expInLevel = expTotal % 100;
    final expPercent = expInLevel / 100;
    final gradient = _bannerGradient(bannerKey);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? Colors.white.withValues(alpha: 0.95) : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        children: [
          Text(
            'Lv.$level',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: expPercent,
                    minHeight: 6,
                    backgroundColor: const Color(0xFFEFE7E3),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF64B5F6)),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$expInLevel/100 EXP',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF9A8E8A)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  LinearGradient? _bannerGradient(String? key) {
    switch (key) {
      case 'banner_pastel':
        return const LinearGradient(
          colors: [Color(0xFFF6C1C9), Color(0xFFF3E7EA)],
        );
      case 'banner_blossom':
        return const LinearGradient(
          colors: [Color(0xFFF7D6D0), Color(0xFFF3E9E6)],
        );
      case 'banner_mint':
        return const LinearGradient(
          colors: [Color(0xFFCDEBD8), Color(0xFFEFF8F2)],
        );
      case 'banner_sunset_7d':
        return const LinearGradient(
          colors: [Color(0xFFFFC3A0), Color(0xFFFFE5B4)],
        );
      case 'banner_season_gold':
        return const LinearGradient(
          colors: [Color(0xFFFFE082), Color(0xFFFFF3C0)],
        );
      case 'banner_season_silver':
        return const LinearGradient(
          colors: [Color(0xFFCFD8DC), Color(0xFFF1F3F4)],
        );
      case 'banner_season_bronze':
        return const LinearGradient(
          colors: [Color(0xFFD7B59A), Color(0xFFF4E8DC)],
        );
      default:
        return null;
    }
  }

  static int _calcMannerScore(int totalGames, int leaveCount, int reportCount) {
    int score = 1000;
    score -= leaveCount * 5;
    score -= reportCount * 3;
    score += (totalGames ~/ 10) * 5;
    return score.clamp(0, 1000);
  }

  Widget _buildMannerLeaveRow({
    required int totalGames,
    required int reportCount,
    required int leaveCount,
  }) {
    final manner = _calcMannerScore(totalGames, leaveCount, reportCount);
    final Color color;
    final IconData icon;
    if (manner >= 800) {
      color = const Color(0xFF4CAF50);
      icon = Icons.sentiment_very_satisfied;
    } else if (manner >= 500) {
      color = const Color(0xFFFF9800);
      icon = Icons.sentiment_neutral;
    } else {
      color = const Color(0xFFE53935);
      icon = Icons.sentiment_very_dissatisfied;
    }
    final l10n = L10n.of(context);
    final boxDeco = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE0D8D4)),
    );
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: boxDeco,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '${l10n.rankingMannerScore} $manner',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: boxDeco,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFE57373),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    l10n.gameDesertions(leaveCount),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF9A6A6A),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection({
    required String title,
    required Color accent,
    required Color background,
    required IconData icon,
    required Color iconColor,
    required String mainText,
    required List<Widget> chips,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: background.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (mainText.isNotEmpty)
                Text(
                  mainText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF8A8A8A)),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentMatchesList(
    List<dynamic> matches,
    String profileNickname,
  ) {
    final l10n = L10n.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0D8D4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.gameRecentMatchesThree,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A8A8A)),
          ),
          const SizedBox(height: 8),
          if (matches.isEmpty)
            Text(
              l10n.gameNoRecentMatches,
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
            )
          else
            Column(
              children: matches
                  .take(3)
                  .map<Widget>((match) => _buildMatchRow(match))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildMatchRow(dynamic match) {
    final l10n = L10n.of(context);
    final isDesertionLoss = match['isDesertionLoss'] == true;
    final won = match['won'] == true;

    String badge;
    Color badgeColor;
    if (isDesertionLoss) {
      badge = l10n.rankingBadgeDesertion;
      badgeColor = const Color(0xFFFF8A65);
    } else if (won) {
      badge = 'W';
      badgeColor = const Color(0xFF81C784);
    } else {
      badge = 'L';
      badgeColor = const Color(0xFFE57373);
    }

    final myRank = match['myRank'] ?? '-';
    final myScore = match['myScore'] ?? 0;
    final date = _formatShortDate(match['createdAt']);
    final isRanked = match['isRanked'] == true;
    final players = match['players'] as List<dynamic>? ?? [];
    final playerText = players.map((p) => p['nickname'] ?? '?').join(', ');
    final scoreText = isDesertionLoss
        ? ''
        : l10n.lobbyRankAndScore(
            myRank.toString(),
            (myScore as num?)?.toInt() ?? 0,
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: isRanked
                  ? const Color(0xFFFFF3E0)
                  : const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isRanked ? l10n.lobbyMatchTypeRanked : l10n.lobbyMatchTypeNormal,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.bold,
                color: isRanked
                    ? const Color(0xFFE65100)
                    : const Color(0xFF9E9E9E),
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
                  playerText,
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
          if (scoreText.isNotEmpty)
            Text(
              scoreText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
        ],
      ),
    );
  }

  String _formatShortDate(dynamic value) {
    try {
      final dt = DateTime.parse(value.toString()).toLocal();
      return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }

  void _showReportDialog(String nickname, GameService game) {
    final reasonController = TextEditingController();
    final l10n = L10n.of(context);
    final reasons = [
      l10n.gameReportReasonAbuse,
      l10n.gameReportReasonSpam,
      l10n.gameReportReasonNickname,
      l10n.gameReportReasonGameplay,
      l10n.gameReportReasonOther,
    ];
    String? selectedReason;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (ctx, setState) {
          final media = MediaQuery.of(ctx);
          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  const Icon(Icons.flag, color: Color(0xFFE57373)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.gameReportTitle(nickname),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: media.size.height * 0.55,
                ),
                child: SingleChildScrollView(
                  child: Column(
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
                        child: Text(
                          l10n.gameReportWarning,
                          style: const TextStyle(
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
                          l10n.gameSelectReason,
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
                          return ChoiceChip(
                            label: Text(
                              r,
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? Colors.white
                                    : const Color(0xFF5A4038),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFFE57373),
                            backgroundColor: const Color(0xFFF5F0EB),
                            onSelected: (_) =>
                                setState(() => selectedReason = r),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        maxLength: 200,
                        decoration: InputDecoration(
                          hintText: l10n.gameReportDetailHint,
                          hintStyle: const TextStyle(fontSize: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.gameClose),
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
                          game.reportUserAction(nickname, reason);
                        },
                  child: Text(l10n.gameReportSubmit),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ContractChangeInfo {
  final String? oldTrump;
  final String? newTrump;
  final int? oldBid;
  final int? newBid;
  _ContractChangeInfo({this.oldTrump, this.newTrump, this.oldBid, this.newBid});
}
