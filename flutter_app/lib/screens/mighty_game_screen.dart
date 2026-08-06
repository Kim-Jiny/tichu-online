import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/game_service.dart';
import '../models/mighty_game_state.dart';
import '../models/player.dart';
import '../widgets/playing_card.dart';
import '../widgets/draggable_chat_panel.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/level_badge.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/seat_chat_bubble.dart';
import '../widgets/bot_avatar.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/player_profile_dialog.dart';
import '../widgets/spectator_controls.dart';
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
  Timer? _dealMissAutoDismissTimer;
  String? _dealMissAutoDismissKey;
  Timer? _settingAutoDismissTimer;
  String? _settingAutoDismissKey;
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

  GameService? _gameService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gameService = context.read<GameService>();
      _readChatCount = _gameService!.chatMessages.length;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateCountdown();
    });
  }

  @override
  void dispose() {
    _seatChat.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    _countdownTimer?.cancel();
    _gameEndCountdownTimer?.cancel();
    _cardViewRequestTimer?.cancel();
    _contractChangeTimer?.cancel();
    _killAutoDismissTimer?.cancel();
    _dealMissAutoDismissTimer?.cancel();
    _settingAutoDismissTimer?.cancel();
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
                // Kitty-exchange panel as a body-level overlay so it can
                // overlap the contract bar (shown higher) on small screens.
                Consumer<GameService>(
                  builder: (context, game, _) {
                    final s = game.mightyGameState;
                    if (s == null || s.phase != 'kitty_exchange') {
                      return const SizedBox.shrink();
                    }
                    return _buildKittyOverlay(game, s);
                  },
                ),
                // Setting-reveal overlay on top of everything (incl. the
                // round-result overlay) so it stays visible when a setting
                // declaration ends the round.
                Consumer<GameService>(
                  builder: (context, game, _) {
                    final s = game.mightyGameState;
                    final ev = s?.lastSettingEvent;
                    if (ev == null) return const SizedBox.shrink();
                    if (_dismissedSettingKey == '${ev.round}-${ev.playerId}') {
                      return const SizedBox.shrink();
                    }
                    return _buildSettingRevealOverlay(
                      ev,
                      trumpSuit: s!.trumpSuit,
                    );
                  },
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
          if (game.isSpectator && game.hasRoom && !game.hasActiveGame) {
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
            final parts = currentMighty.replaceFirst('mighty_', '').split('_');
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
                    mightyCard != null && myCards.contains(mightyCard);
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
                  _friendCardSelection = 'mighty_${_friendSuit}_$_friendRank';
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
        if (_selectedCard != null && !state.myCards.contains(_selectedCard)) {
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
          final killKey = '${state.round}-${state.lastKillEvent!.targetCardId}';
          final isActive = _dismissedKillKey != killKey;
          if (isActive && _killAutoDismissKey != killKey) {
            _killAutoDismissKey = killKey;
            _killAutoDismissTimer?.cancel();
            _killAutoDismissTimer = Timer(const Duration(seconds: 4), () {
              if (!mounted) return;
              setState(() => _dismissedKillKey = killKey);
            });
          } else if (!isActive && _killAutoDismissKey == killKey) {
            _killAutoDismissTimer?.cancel();
          }
        }

        // Deal-miss reveal auto-dismiss (same 5s pattern as kill so the
        // full-screen overlay never blocks the table indefinitely).
        if (state.lastDealMissEvent != null) {
          final dmKey =
              '${state.lastDealMissEvent!.round}-${state.lastDealMissEvent!.playerId}';
          final isActive = _dismissedDealMissKey != dmKey;
          if (isActive && _dealMissAutoDismissKey != dmKey) {
            _dealMissAutoDismissKey = dmKey;
            _dealMissAutoDismissTimer?.cancel();
            _dealMissAutoDismissTimer = Timer(const Duration(seconds: 5), () {
              if (!mounted) return;
              setState(() => _dismissedDealMissKey = dmKey);
            });
          } else if (!isActive && _dealMissAutoDismissKey == dmKey) {
            _dealMissAutoDismissTimer?.cancel();
          }
        }

        // Setting reveal auto-dismiss (same pattern).
        if (state.lastSettingEvent != null) {
          final stKey =
              '${state.lastSettingEvent!.round}-${state.lastSettingEvent!.playerId}';
          final isActive = _dismissedSettingKey != stKey;
          if (isActive && _settingAutoDismissKey != stKey) {
            _settingAutoDismissKey = stKey;
            _settingAutoDismissTimer?.cancel();
            _settingAutoDismissTimer = Timer(const Duration(seconds: 5), () {
              if (!mounted) return;
              setState(() => _dismissedSettingKey = stKey);
            });
          } else if (!isActive && _settingAutoDismissKey == stKey) {
            _settingAutoDismissTimer?.cancel();
          }
        }

        // Kitty-phase contract-change detection: flash a banner when
        // the declarer changes trump or raises the bid so the other
        // players notice the contract shift.
        if (state.phase == 'kitty_exchange' && state.declarer != null) {
          final currTrump = state.trumpSuit;
          final currBid = (state.currentBid['points'] as num?)?.toInt();
          if (_kittyContractTrump != null && _kittyContractBid != null) {
            final trumpChanged =
                currTrump != null && currTrump != _kittyContractTrump;
            final bidRaised = currBid != null && currBid > _kittyContractBid!;
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
          if (_kittyContractTrump != null || _kittyContractBid != null) {
            _kittyContractTrump = null;
            _kittyContractBid = null;
          }
        }

        return Stack(
          children: [
            Column(
              children: [
                _buildTopBar(state, game),
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
            // The declarer chose the kill target, so they don't need
            // the reveal popup — only show it to everyone else.
            if (state.lastKillEvent != null &&
                game.playerId != state.declarer &&
                _dismissedKillKey !=
                    '${state.round}-${state.lastKillEvent!.targetCardId}')
              _buildKillRevealOverlay(state, state.lastKillEvent!),
            // NOTE: the setting-reveal overlay is rendered at the top
            // of the body Stack (above the round-result overlay) so it
            // isn't hidden behind the round result.
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
            alignment: isRoundEnd ? Alignment.bottomCenter : Alignment.center,
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
    // Stack so the floating DraggableChatPanel (a Positioned) overlays the
    // waiting-room layout — it can't live inside the Column.
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.90),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE0D8D4)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => game.leaveRoom(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Color(0xFF5A4038),
                      ),
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
                          if (_chatOpen)
                            _readChatCount = game.chatMessages.length;
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
                                padding: const EdgeInsets.only(top: 6),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: wide ? 2 : 1,
                                      mainAxisSpacing: 10,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: wide ? 4.8 : 4.4,
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
            ],
          ),
        ),
        if (_chatOpen) _buildChatPanel(game),
      ],
    );
  }



  /// The last thing each player said, over their waiting-room seat.
  late final SeatChatBubbles _seatChat = SeatChatBubbles(() {
    if (mounted) setState(() {});
  });

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

  /// Avatar for a waiting-room seat: photo, bot art, or the default
  /// silhouette, with the level as a corner badge.
  Widget _buildWaitingSlotAvatar(GameService game, Player player) {
    const size = 44.0;
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
                size: 26,
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

  Widget _buildWaitingSlot(GameService game, Player? player, int slotIndex) {
    _seatChat.consume(game);
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
                // The level used to be drawn AS the avatar when a player had no
                // photo, which put a number where every other screen puts a
                // face. It belongs in the corner badge, the way the lobby and
                // the Tichu spectator room do it — and the bot tag comes back
                // with it, so you can still tell the bots apart.
                _buildWaitingSlotAvatar(game, player),
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
              child: Text('👑', style: TextStyle(fontSize: 18, height: 1.0)),
            ),
          // What this player just said, for a couple of seconds.
          ?_seatChatBubble(player.name),
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

    // Spectators get the shared flat header (see SpectatorHeader) so all four
    // games' spectator bars look alike; the chip row below stays for players.
    if (game.isSpectator) {
      final l10n = L10n.of(context);
      final roundText = state.phase == 'round_end'
          ? l10n.mtRoundOnly(state.round.toString())
          : l10n.mtRoundPhase(state.round.toString(), _phaseLabel(state.phase));
      return Column(
        children: [
          SpectatorHeader(
            game: game,
            statusLine: roundText,
            statusTrailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.spectatorTargetScore(game.roomTargetScore),
                  style: const TextStyle(
                    color: Color(0xFFA89C96),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // Same slot Tichu uses for its tappable score chips.
                const SizedBox(width: 8),
                SpectatorStatusChip(
                  icon: Icons.leaderboard_outlined,
                  label: l10n.gameScoreHistory,
                  onTap: () => _showScoreHistoryDialog(state, game),
                ),
              ],
            ),
            actions: [
              _buildTopActionButton(
                icon: Icons.chat_bubble_outline,
                active: _chatOpen,
                badgeCount: _chatOpen
                    ? 0
                    : (game.chatMessages.length - _readChatCount).clamp(0, 99),
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
              const SizedBox(width: 6),
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
          if (showContractInfo) _buildContractInfoBar(state, game),
        ],
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          // The finish line is not here: as a bare number beside the round it
          // read as part of the score rather than as a goal. It lives in the
          // score-history popup, spelled out.
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
                          ? L10n.of(context).mtRoundOnly(state.round.toString())
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
              // Shown from round 1 on: the popup itself says when there is
              // nothing to show, rather than the button appearing later and
              // moving everything beside it.
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _buildTopActionButton(
                  icon: Icons.leaderboard_outlined,
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
            const Divider(height: 16, color: Color(0xFFEDE5E0)),
            _buildCardViewPrefSection(game),
          ],
        ),
      ),
    );
  }

  Widget _buildCardViewPrefSection(GameService game) {
    final l10n = L10n.of(context);
    Widget radio({
      required String value,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      final selected = game.cardViewPref == value;
      return GestureDetector(
        onTap: () => game.setCardViewPref(value),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? color : const Color(0xFFE6DCE8),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? color : const Color(0xFF999999),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected ? color : const Color(0xFF5A4038),
                  ),
                ),
              ),
              if (selected) Icon(Icons.check, size: 14, color: color),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.gameCardViewPolicyTitle,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF5A4038),
          ),
        ),
        const SizedBox(height: 6),
        radio(
          value: 'ask',
          label: l10n.gameCardViewPolicyAsk,
          icon: Icons.help_outline,
          color: const Color(0xFF6A6090),
        ),
        radio(
          value: 'always_allow',
          label: l10n.gameCardViewPolicyAllow,
          icon: Icons.check_circle,
          color: const Color(0xFF4CAF50),
        ),
        radio(
          value: 'always_deny',
          label: l10n.gameCardViewPolicyDeny,
          icon: Icons.block,
          color: const Color(0xFFE53935),
        ),
      ],
    );
  }

  Widget _buildMoreMenu(GameService game) {
    final hasViewers = game.cardViewers.isNotEmpty;
    return Positioned(
      top: 56,
      right: 8,
      child: Container(
        // Players see 4 actions (incl. card-view); spectators have no cards so
        // the card-view button is hidden and the menu is narrower.
        width: game.isSpectator ? 158 : 210,
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
            // Card-view policy controls — players only (spectators have no
            // cards for anyone to view).
            if (!game.isSpectator)
              _buildTopActionButton(
                icon: Icons.visibility,
                active: _viewersOpen,
                badgeCount: hasViewers ? game.cardViewers.length : 0,
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
                  _moreOpen = false;
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
                // Spectators can leave immediately (no game state to lose);
                // only players get the "really leave?" confirm. Matches SK.
                if (game.isSpectator) {
                  game.leaveRoom();
                } else {
                  _showExitConfirmDialog(game);
                }
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
    final hasFriendInfo = friendCardSuit != null || friendSpecialText != null;
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
      final bidPointsText = L10n.of(
        context,
      ).mtContractWithPoints(bidPoints.toInt());
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
                L10n.of(context).mtDealMissPool(state.dealMissPool.toString()),
                10,
              ) +
              16
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Half-center span occupies width/2 ± centerEstimate/2.
          final centerRight = (width + centerEstimate) / 2;
          final dealMissLeftIfFull = width - dealMissFullWidth;
          final useCompactDealMiss =
              state.dealMissPool > 0 && centerRight > dealMissLeftIfFull - 6;

          final centerContent = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leaderName.isNotEmpty)
                Text(
                  leaderName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF5A4038),
                  ),
                ),
              if (leaderName.isNotEmpty && hasBid) const SizedBox(width: 7),
              if (hasBid)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _bidAccentColor(bidSuit?.toString()),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SuitIcon(
                        suit: bidSuit?.toString() ?? '',
                        size: 14,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        L10n.of(
                          context,
                        ).mtContractWithPoints(bidPoints.toInt()),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!isBidding && hasFriendInfo) ...[
                const SizedBox(width: 7),
                const Text(
                  '/',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A7A72)),
                ),
                const SizedBox(width: 7),
                if (friendCardSuit != null) ...[
                  SuitIcon(
                    suit: friendCardSuit,
                    size: 13,
                    color: _bidAccentColor(friendCardSuit),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$friendCardRank$friendSuffixText',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _bidAccentColor(friendCardSuit),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else
                  Text(
                    '${friendSpecialText ?? ''}$friendSuffixText',
                    style: const TextStyle(
                      fontSize: 13,
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
                Align(alignment: Alignment.centerRight, child: dealMissChip),
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
        SuitIcon(suit: suit, size: 14, color: tone),
        const SizedBox(width: 3),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 14,
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
    return SpectatorActionButton(
      icon: icon,
      active: active,
      onTap: onTap,
      badgeCount: badgeCount,
      iconColor: iconColor,
    );
  }

  void _scrollChatToBottom() {
    // DraggableChatPanel's list is reverse:true, so offset 0 == newest.
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

  Widget _buildChatPanel(GameService game) {
    if (game.chatMessages.length != _lastChatMessageCount) {
      _lastChatMessageCount = game.chatMessages.length;
      _readChatCount = game.chatMessages.length;
      _scrollChatToBottom();
    }
    return DraggableChatPanel(
      accentColor: const Color(0xFF1565C0),
      sendIconColor: const Color(0xFF1565C0),
      title: L10n.of(context).mtChat,
      hintText: L10n.of(context).mtTypeMessage,
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
        final isBlocked = sender.isNotEmpty && game.isBlocked(sender);
        if (isBlocked) return const SizedBox.shrink();
        return _buildChatBubble(sender, message, isMe, game);
      },
    );
  }

  /// The shared bubble, like every other screen. Mighty had its own copy that
  /// drew a grey circle with the first letter of the nickname and swallowed
  /// taps — so this was the one chat panel with no profile photo and no way to
  /// open a profile from it.
  Widget _buildChatBubble(
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
      mineColor: const Color(0xFF1565C0),
      onTap: sender.isEmpty
          ? null
          : () => _showPlayerProfileDialog(
              sender,
              game,
              isBot: _isBotNickname(game, sender),
            ),
    );
  }

  /// Bots have no account, so their bubble must open the bot blurb rather than
  /// a profile lookup that will never resolve.
  bool _isBotNickname(GameService game, String nickname) {
    final players = game.mightyGameState?.players ?? const [];
    for (final p in players) {
      if (p.name == nickname) return p.id.startsWith('bot_');
    }
    return false;
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
          fontSize: 13,
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
          SuitIcon(suit: suit, size: 13, color: accent),
          const SizedBox(width: 3),
          Text(
            '$points',
            style: TextStyle(
              fontSize: 13,
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
    _seatChat.consume(game);
    final isLandscape =
        !kIsWeb &&
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
          // Sized from the board it has to fit in, not from constants tuned on
          // one phone. Reference is a 360×420 board (a 6.1" portrait); a bigger
          // device gets proportionally bigger seats and cards instead of the
          // same ones marooned in empty space.
          final boardScale = math
              .min(width / 360.0, height / 400.0)
              .clamp(0.78, 1.45);
          // Two seat columns plus a gap have to fit across, and two rows have
          // to fit inside the ring — on a narrow or short board the seat gives
          // way rather than the seats sliding into each other.
          // Board drop is not known yet here and only shifts the ring down a
          // little, so the fit uses the undropped centre — a slightly
          // conservative estimate, which is the safe direction.
          final centerYForFit = isLandscape ? height * 0.42 : height * 0.47;
          final seatFit = math.min(
            (width - 20) / 2.42 / 116.0,
            (centerYForFit * 0.9) / 126.0,
          );
          final seatScale = math.min(boardScale, seatFit).clamp(0.62, 1.45);
          final seatWidth = 116.0 * seatScale;
          // Tall enough for the enlarged avatar to render at full size — the
          // label is FittedBox'd, so a box that is too short shrinks the photo
          // and the nickname with it instead of growing them.
          final seatHeight = 126.0 * seatScale;
          final playedCardHeight = 72.0 * boardScale;
          final playedCardWidth = playedCardHeight * 0.7;
          // The played card is laid ON the seat rather than under it: the
          // avatar is twice the size it was, and stacking the card below would
          // push every seat outward until the board no longer fits.
          //
          // Centred on the photo, not on the seat box: the label is top-aligned
          // inside the box, so the photo's middle sits a role-label and half an
          // avatar below the top edge. Sharing a centre is what makes the card
          // read as "this seat played it" rather than as a card parked nearby.
          final seatMetrics = _mightySeatMetrics(seatWidth, seatHeight);
          final playedCardTopOffset =
              seatMetrics.photoCentre - playedCardHeight / 2;
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
            // Six seats stack three to a side, and the ring's vertical radius
            // is what they have to share. It is capped by how far the centre
            // sits from the top edge, so at six players the ring moves down —
            // that is room the board has and the seats were not using.
            final sixUp = playerCount >= 6;
            final centerY =
                height *
                    (isLandscape
                        ? (sixUp ? 0.42 : 0.39)
                        : (sixUp ? 0.47 : 0.41)) +
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
                          // Six seats take the middle of the board, so the
                          // status line sits under the ring rather than inside
                          // it — at the old height the lower two seats ran
                          // straight through it.
                          : sixUp
                          ? (isLandscape ? 0.62 : 0.78)
                          : (isLandscape ? 0.36 : 0.46),
                    ),
                    child: isBidding
                        ? _buildBiddingCenterInfo(state)
                        : isKillSelect
                        ? _buildKillCenterInfo(state)
                        : Transform.translate(
                            offset: Offset(
                              0,
                              sixUp
                                  ? spectatorBoardDrop
                                  : (isLandscape ? -18 : -26) +
                                        spectatorBoardDrop,
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
                        top: seatTop + playedCardTopOffset,
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
          // Dropped from 0.41: the ring's vertical radius is capped by how far
          // the top seat can sit above centre, and with the taller seats that
          // cap was what pushed the two side seats into each other. There is
          // empty board below them to give.
          final centerY =
              (isLandscape ? height * 0.42 : height * 0.47) + playerBoardDrop;
          final maxSeatRadiusY = math.max(0.0, centerY - seatHeight / 2 - 6);
          final seatRadiusY = math.min(
            height * (isLandscape ? 0.35 : 0.36),
            math.min(
              _mightySeatRadiusYCap(height, spectator: false),
              maxSeatRadiusY,
            ),
          );
          // How far the side seats have to sit off the horizontal for the two
          // on each side to clear each other: their vertical gap is
          // 2·R·sin(offset). On a tall board this stays at the 25° that looks
          // best; on a short one it opens up instead of letting them overlap.
          //
          // Computed before the horizontal radius now: the seats sit at an
          // angle, so how far out they land depends on it.
          final sideOffsetDeg = seatRadiusY <= 0
              ? 25.0
              : (math.asin(
                      (((seatHeight + 8) / (2 * seatRadiusY)).clamp(
                        0.42,
                        0.80,
                      )).toDouble(),
                    ) *
                    180 /
                    math.pi);
          // 옆자리는 정면(±90°)이 아니라 비스듬히 앉는다. 그 x 이동량은
          // R·|cos| 이므로, 반경을 마치 정면인 것처럼 제한하면 |cos| 만큼
          // 화면 좌우가 남는다 — 5인에서 |cos|≈0.82 라 30dp 넘게 놀았다.
          // 실제 이동량 기준으로 잡아 그 여백을 쓴다.
          final spreadCos = _mightyWidestSeatCos(opponentCount, sideOffsetDeg);
          final maxSeatRadiusX = math.max(
            0.0,
            (centerX - seatWidth / 2 - 8) / spreadCos,
          );
          final seatRadiusX = math.min(
            width * _mightySeatRadiusXFactor(opponentCount),
            math.min(
              _mightySeatRadiusXCap(width, opponentCount, spectator: false),
              maxSeatRadiusX,
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
                            _mightyTopSeatAngleForIndex(
                              i,
                              opponents.length,
                              sideOffsetDeg: sideOffsetDeg,
                            ),
                          ) +
                      _mightySmallDeviceSideSeatDrop(
                        _mightyTopSeatAngleForIndex(
                          i,
                          opponents.length,
                          sideOffsetDeg: sideOffsetDeg,
                        ),
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
                    sideOffsetDeg: sideOffsetDeg,
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
                      sideOffsetDeg: sideOffsetDeg,
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
                      top: seatTop + playedCardTopOffset,
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
        // NOTE: the kitty-exchange panel is rendered at the top of the body
        // Stack (above the contract bar) so it can overlap it on small screens.
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
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFFD84315),
        ),
      );
    } else if (isDeclarer && isPartner) {
      // 초구 프렌즈: the declarer won the first trick, so they are BOTH the
      // 주공 and the 프렌드 — surface both roles at once.
      roleLabel = RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          children: [
            TextSpan(
              text: L10n.of(context).mtDeclarer,
              style: const TextStyle(color: Color(0xFFFF8A00)),
            ),
            const TextSpan(
              text: '·',
              style: TextStyle(color: Color(0xFF8A7A72)),
            ),
            TextSpan(
              text: L10n.of(context).mtFriend,
              style: const TextStyle(color: Color(0xFF4CAF50)),
            ),
          ],
        ),
      );
    } else if (isDeclarer) {
      roleLabel = Text(
        L10n.of(context).mtDeclarer,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: Color(0xFFFF8A00),
        ),
      );
    } else if (isPartner) {
      roleLabel = Text(
        L10n.of(context).mtFriend,
        style: const TextStyle(
          fontSize: 10,
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
        // The tap is overloaded (card view for spectators, point cards, then
        // profile), so for a spectator it never reaches the profile. Long-press
        // goes straight there, as in the SK and LL seats.
        onLongPress: () => _showPlayerProfileDialog(
          player.name,
          game,
          isBot: player.id.startsWith('bot_'),
        ),
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
            final roleLabelHeight = compact ? 15.0 : 16.0;
            final offlineIconSize = compact ? 10.0 : 11.0;
            final nameFontSize = compact ? 10.0 : 11.0;
            final scoreFontSize = compact ? 13.0 : 15.0;
            final metaFontSize = compact ? 8.0 : 8.5;
            final spacing = compact ? 1.0 : 2.0;
            // Same source as the board's card placement — see
            // _mightySeatMetrics.
            final avatarDiameter = _mightySeatMetrics(
              constraints.maxWidth,
              constraints.maxHeight,
            ).avatar;
            // Hugs the photo instead of taking a fixed 70% of the seat box —
            // the leftover width was empty tint either side of the avatar.
            final contentWidth = math.max(
              avatarDiameter + 6,
              math.min(
                (constraints.maxWidth - horizontalPadding * 2) * 0.7,
                avatarDiameter + 22,
              ),
            );
            final labelTint = highlighted
                ? const Color(0xFFE7F2FF).withValues(alpha: 0.92)
                : isCurrentTurn
                ? const Color(0xFFFFF0C9).withValues(alpha: 0.88)
                : const Color(0xFFFFFCFA).withValues(alpha: 0.64);

            return SeatBubbleAnchor(
              // 말풍선은 좌석 Stack 안이 아니라 오버레이에 그린다 —
              // 안쪽에 두면 나중에 그려지는 좌석·카드가 그대로 덮는다.
              text: _seatChat.textFor(player.name),
              suppressed: _chatOpen,
              child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: verticalPadding,
                  ),
                  decoration: const BoxDecoration(),
                  // Top-aligned, not centred: the board places the played card
                  // from the seat's top edge, so a label that floats vertically
                  // puts the card slightly off the photo.
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.topCenter,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.topCenter,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                // Half of what it was: with a 56px photo the old
                                // padding read as a frame around the seat rather
                                // than as the seat itself.
                                padding: EdgeInsets.symmetric(
                                  horizontal: compact ? 3 : 4,
                                  vertical: compact ? 2 : 3,
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
                                          width: (isDeclarer || isPartner)
                                              ? 3.5
                                              : 1.5,
                                        )
                                      : null,
                                ),
                                child: SizedBox(
                                  width: contentWidth,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        height: roleLabelHeight,
                                        child: Center(child: roleLabel),
                                      ),
                                      // Own row rather than inline before the
                                      // name (same as SK/LL), and rendered for
                                      // EVERY seat — photo-less seats get the
                                      // default silhouette. Not cosmetic: the
                                      // label scales down to fit the seat box, so
                                      // when only some seats had an avatar their
                                      // labels shrank (smaller name and all) while
                                      // avatar-less seats rendered full size — the
                                      // seats came out visibly different sizes.
                                      Padding(
                                        padding: EdgeInsets.only(
                                          bottom: spacing,
                                        ),
                                        child: ProfileAvatar(
                                          photoUrl: game.resolvePhotoUrl(
                                            player.photoUrl,
                                          ),
                                          size: avatarDiameter,
                                          blocked: game.blockedUsers.contains(
                                            player.name,
                                          ),
                                          fallback: player.isBot
                                              ? BotAvatar(
                                                  size: avatarDiameter,
                                                  name: player.name,
                                                )
                                              : DefaultAvatar(
                                                  size: avatarDiameter,
                                                ),
                                        ),
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
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
                                      // Only when there is a count: the always-
                                      // reserved row pushed the label over the seat
                                      // box, and the FittedBox paid for it by
                                      // scaling the avatar down.
                                      if (player.timeoutCount > 0) ...[
                                        SizedBox(height: spacing),
                                        SizedBox(
                                          height: timeoutHeight,
                                          child: Text(
                                            '⏱ ${player.timeoutCount}/3',
                                            style: TextStyle(
                                              fontSize: metaFontSize,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFFE65100),
                                            ),
                                          ),
                                        ),
                                      ],
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
                                  left: -6,
                                  top: -6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: const Color(0xFFE53935),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.12,
                                          ),
                                          blurRadius: 3,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.style,
                                          size: 10,
                                          color: Color(0xFFE53935),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '${player.pointCount}',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFE53935),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (hasPointCards)
                          Positioned(
                            left: 0,
                            right: 0,
                            // 프로필 박스 바로 밑에 붙인다. -26 은 카드 아래로
                            // 한 줄 띄운 느낌이라 좌석과 따로 노는 것처럼 보였다.
                            bottom: -17,
                            child: Center(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                // 먹은 패를 눌러도 배지를 누른 것과 같은 팝업이
                                // 뜬다. 카드-보기 요청 모드일 때 좌석 탭은 그쪽에
                                // 쓰이므로, 이 줄만은 항상 목록을 연다.
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _showPointCardsDialog(player),
                                  child: _buildSeatPointCards(player),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
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

  /// [sideOffsetDeg] widens the two seats on each side away from the
  /// horizontal axis. The vertical gap between them is 2·R·sin(offset), so on a
  /// short board the caller passes a bigger angle rather than letting the seats
  /// grow into each other.
  /// Where the photo's centre sits inside a seat box, measured from its top.
  ///
  /// The board positions the played card from this, and the seat itself sizes
  /// its avatar from it — one function so the two cannot drift apart, which is
  /// exactly what made the card land slightly off the photo.
  /// 좌석 중 좌우로 가장 멀리 나가는 자리의 |cos|.
  ///
  /// 링 반경을 화면 폭으로 제한할 때 쓴다. 좌석이 정면에 앉지 않으면 x 이동량은
  /// R 보다 작아서, 이걸 안 나누면 그만큼 좌우 여백이 그냥 남는다.
  double _mightyWidestSeatCos(int count, double sideOffsetDeg) {
    final angles = <double>[
      for (int i = 0; i < count; i++)
        _mightyTopSeatAngleForIndex(i, count, sideOffsetDeg: sideOffsetDeg),
    ];
    var widest = 0.0;
    for (final a in angles) {
      final c = math.cos(a).abs();
      if (c > widest) widest = c;
    }
    // 전부 세로에 가까우면 0 에 가까워져 반경이 발산한다 — 하한을 둔다.
    return widest.clamp(0.35, 1.0).toDouble();
  }

  static ({double avatar, double photoCentre}) _mightySeatMetrics(
    double seatWidth,
    double seatHeight,
  ) {
    final compact = seatHeight <= 70 || seatWidth <= 96;
    final verticalPadding = compact ? 4.0 : 6.0;
    final labelPadding = compact ? 2.0 : 3.0;
    final roleLabelHeight = compact ? 15.0 : 16.0;
    // Height alone used to decide this, so making the window wider changed
    // nothing — and the ceiling was a phone-sized 92, which a desktop board
    // reaches immediately and then stops. On web, let the seat's width have a
    // say (so the photo can never outgrow its own box) and raise the ceiling.
    // Native keeps the original number exactly. The web ceiling came down
    // with the board (148 was picked against a 1.6 scale, this is 1.3).
    final avatar = kIsWeb
        ? math
              .min(seatHeight * 0.60, seatWidth * 0.62)
              .clamp(40.0, 120.0)
              .toDouble()
        : (seatHeight * 0.60).clamp(40.0, 92.0).toDouble();
    return (
      avatar: avatar,
      photoCentre:
          verticalPadding + labelPadding + roleLabelHeight + avatar / 2,
    );
  }

  double _mightyTopSeatAngleForIndex(
    int index,
    int playerCount, {
    double? sideOffsetDeg,
  }) {
    if (playerCount <= 1) return math.pi * 1.5;
    if (playerCount == 5 && sideOffsetDeg != null) {
      final o = sideOffsetDeg;
      final angles = [180 - o, 180 + o, 270.0, 360 - o, 360 + o];
      return angles[index] * math.pi / 180;
    }
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
      case 5:
        // top(270) + two vertical columns. Lower seats mirror the upper ones
        // across the horizontal axis so each side shares the same X: left
        // column at 207.5/152.5 (cos ≈ -0.887), right at 332.5/387.5
        // (cos ≈ +0.887). Order: lower-left, upper-left, top, upper-right,
        // lower-right.
        // Spread wider than the old ±17.5°: the vertical gap between the two
        // seats on a side is 2·R·sin(offset), and with the taller seat boxes
        // ±17.5° left them ~4dp short of clearing each other.
        return const [145.0, 215.0, 270.0, 325.0, 395.0];
      default:
        return null;
    }
  }

  List<double>? _mightyCustomSpectatorSeatAnglesDeg(int count) {
    switch (count) {
      case 6:
        // Pushed away from the horizontal (was 142/188/236 a side): three seats
        // per side have to share the ring's vertical span, and the enlarged
        // seat boxes no longer fit in the old spacing. Spreading them costs
        // nothing — the seats keep their size, they just sit further apart.
        return const [135, 185, 238, 302, 355, 405];
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
    // Raised with the seat box: a 132-tall seat needs more room between rings
    // than a 96-tall one, or the rows sit on top of each other.
    final base = spectator ? 262.0 : 270.0;
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

  // Compact strip of ONE player's captured point cards, shown under their seat
  // profile (replaces the old clustered opposition bar). Constrained width so a
  // large capture wraps to a second row instead of overflowing the seat.
  Widget _buildSeatPointCards(MightyPlayer player) {
    final cards = player.pointCards;
    if (cards.isEmpty) return const SizedBox.shrink();
    const maxShown = 5;
    final shown = cards.take(maxShown).toList();
    final extra = cards.length - shown.length;
    // Single row (capped at 5 cards + "+N") so a big capture doesn't make the
    // strip tall and shrink the seat profile via the FittedBox scale-down.
    final items = <Widget>[
      for (final cardId in shown)
        PlayingCard(
          cardId: _displayCardId(cardId),
          width: 15,
          height: 21,
          isInteractive: false,
        ),
      if (extra > 0)
        Container(
          width: 17,
          height: 21,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF5A4038),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '+$extra',
            style: const TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            items[i],
          ],
        ],
      ),
    );
  }

  // My own captured point cards — the table seat for `position == 'self'` is
  // omitted, so this is the only place my score cards appear. Shown as a
  // compact tappable chip on the prev-trick button line: point count + up to
  // 5 mini cards + "+N", mirroring the other players' seat display. Tapping
  // opens the same full point-card popup.
  // My own role chip — only for 주공 / 프렌드 (opposition intentionally shown
  // as nothing). Friend is surfaced as soon as it's knowable to me (I hold the
  // named card) even before the public reveal. Returns null when I have no such
  // role to show.
  Widget? _buildMyRoleBadge(MightyGameStateData state, GameService game) {
    if (game.isSpectator) return null;
    final myId = game.playerId;
    if (myId.isEmpty || state.declarer == null) return null;

    final String label;
    final Color color;
    if (myId == state.declarer) {
      label = L10n.of(context).mtDeclarer;
      color = const Color(0xFFFF8A00);
    } else {
      final fc = state.friendCard;
      final iHoldFriendCard =
          fc != null &&
          fc != 'no_friend' &&
          fc != 'first_trick' &&
          state.myCards.contains(fc);
      final amFriend =
          fc != null &&
          ((state.friendRevealed && myId == state.partner) || iHoldFriendCard);
      if (!amFriend) return null;
      label = L10n.of(context).mtFriend;
      color = const Color(0xFF4CAF50);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 13, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyPointCardStrip(MightyGameStateData state) {
    final me = state.players.cast<MightyPlayer?>().firstWhere(
      (p) => p?.position == 'self',
      orElse: () => null,
    );
    final cards = me?.pointCards ?? const <String>[];
    if (cards.isEmpty || me == null) return const SizedBox.shrink();
    const maxShown = 5;
    final shown = cards.take(maxShown).toList();
    final extra = cards.length - shown.length;
    final cardItems = <Widget>[
      for (final cardId in shown)
        PlayingCard(
          cardId: _displayCardId(cardId),
          width: 16,
          height: 22,
          isInteractive: false,
        ),
      if (extra > 0)
        Container(
          width: 18,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF5A4038),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            '+$extra',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showPointCardsDialog(me),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF3ECE6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.workspace_premium,
              size: 15,
              color: Color(0xFF8A7A72),
            ),
            const SizedBox(width: 3),
            Text(
              '${me.pointCount}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFF5A4038),
              ),
            ),
            const SizedBox(width: 6),
            for (var i = 0; i < cardItems.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              cardItems[i],
            ],
          ],
        ),
      ),
    );
  }

  void _showPointCardsDialog(MightyPlayer p) {
    showDialog(
      context: context,
      builder: (ctx) {
        final cards = p.pointCards;
        return Dialog(
          backgroundColor: Colors.white,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 제목 줄: 누구 것인지 + 몇 장인지. 장수는 배지와 같은 모양으로
                // 두어 좌석에서 누른 그 표시와 같은 것임이 바로 보이게 한다.
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF4A3A32),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: const Color(0xFFE53935),
                          width: 1.2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.style,
                            size: 12,
                            color: Color(0xFFE53935),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${p.pointCount}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE53935),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (cards.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: Text(
                        L10n.of(context).mtNoPointCards,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF8A7A72),
                        ),
                      ),
                    ),
                  )
                else
                  // 카드가 많아지면(최대 20장) 세로로 늘어나 화면을 넘기므로
                  // 스크롤 영역 안에 둔다.
                  Flexible(
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final cardId in cards)
                            PlayingCard(
                              cardId: _displayCardId(cardId),
                              width: 42,
                              height: 59,
                              isInteractive: false,
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(L10n.of(context).mtClose),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Trick Area ──
  // Consolidated game-state header for the center trick panel: round, trick
  // number (n/10) and lead suit (when a trick is in progress). Trump counting
  // lives beside the hand instead. Keeps the at-a-glance info in one readable
  // place instead of scattered around the table.
  // Centre indicator during bidding — mainly for spectators, who have no
  // bidding panel of their own and otherwise wouldn't see the turn timer.
  Widget _buildBiddingCenterInfo(MightyGameStateData state) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.gavel, size: 20, color: Color(0xFF1565C0)),
            const SizedBox(height: 4),
            Text(
              L10n.of(context).mtBidInProgress,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF5A4038),
              ),
            ),
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

  // Centre indicator during the 6p kill-select phase — shown to everyone but
  // the declarer (who has their own kill panel), so others/spectators know the
  // declarer is choosing a kill target and how long they have.
  Widget _buildKillCenterInfo(MightyGameStateData state) {
    final declarerName = state.declarer == null
        ? ''
        : (state.players
                  .where((p) => p.id == state.declarer)
                  .map((p) => p.name)
                  .firstOrNull ??
              '');
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.dangerous, size: 20, color: Color(0xFFD84315)),
            const SizedBox(height: 4),
            SizedBox(
              width: 180,
              child: Text(
                L10n.of(context).mtKillPhaseWait(declarerName),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
            ),
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

  Widget _buildTrickArea(MightyGameStateData state, GameService game) {
    if (state.currentTrick.isEmpty) {
      // During the kitty exchange spectators see the status here in the centre;
      // players (incl. non-declarers) see it above their own hand instead.
      final isKittyWait = state.phase == 'kitty_exchange' && game.isSpectator;
      return Center(
        child: Container(
          // 내용에 맞춰 줄어든다. 고정 200dp 라 "대기 중…" 한 줄일 때도 양옆으로
          // 길어져서, 좌석이 바깥으로 벌어진 뒤로는 서로 겹쳤다.
          constraints: const BoxConstraints(minWidth: 116, maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isKittyWait ? Icons.swap_horiz : Icons.style,
                size: 20,
                color: const Color(0xFF8A7A72),
              ),
              const SizedBox(height: 4),
              Text(
                isKittyWait
                    ? L10n.of(context).mtExchangingKitty
                    : state.isMyTurn
                    ? L10n.of(context).mtYourTurn
                    : L10n.of(context).mtWaiting,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF5A4038),
                ),
              ),
              if (_remainingSeconds > 0 && (state.isMyTurn || isKittyWait))
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

    // Contract (공약) is already shown in the top info bar, so the center
    // trick box only surfaces the LEAD suit — rendered big and faded as a
    // background watermark so it reads at a glance.
    final accent = leadSuit != null
        ? _bidAccentColor(leadSuit)
        : const Color(0xFF8A7A72);

    return Center(
      child: Container(
        // 같은 이유로 고정 폭 대신 내용 폭 + 하한. 배경 무늬는 FittedBox 라
        // 상자가 좁아지면 같이 작아진다.
        constraints: const BoxConstraints(
          minWidth: 116,
          maxWidth: 150,
          minHeight: 74,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.68),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Big faded lead-suit watermark — FittedBox scales it to fit the
            // box so it's always fully visible (never clipped).
            if (leadSuit != null)
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: SuitIcon(
                      suit: leadSuit,
                      size: 100,
                      color: accent.withValues(alpha: 0.15),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leadSuit != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          '${L10n.of(context).mtLead} ',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                        SuitIcon(suit: leadSuit, size: 18, color: accent),
                      ],
                    )
                  else
                    const Icon(Icons.style, size: 20, color: Color(0xFF8A7A72)),
                  // Turn timer
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

  // Sentinel used to insert a SuitIcon into a localized message that takes
  // a {suit} placeholder. Picked so it won't collide with real translations.
  // Written as escapes, not raw NULs: a literal NUL in the source makes grep,
  // diff and review tools treat this 300KB file as binary and silently skip it.
  static const String _trumpChangeSentinel = '\u0000SUIT\u0000';

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
            child: SuitIcon(suit: suit, size: 13, color: _bidAccentColor(suit)),
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

  // Full-screen host for the kitty panel.
  Widget _buildKittyOverlay(GameService game, MightyGameStateData state) {
    // Only the DECLARER sees the kitty panel. Others / spectators get nothing
    // here — the "exchanging" note was redundant and overlapped the kill-reveal
    // popup in 6p, making both unreadable.
    if (!state.isMyTurn) return const SizedBox.shrink();
    // The DECLARER's interactive panel sits just above their hand (bottom-
    // anchored) and grows upward — over the contract bar if needed — scrolling
    // when it would reach the top. The hand area below stays tappable.
    final topInset = MediaQuery.of(context).padding.top;
    return SizedBox.expand(
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          top: topInset + 42,
          bottom: 210,
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: SingleChildScrollView(child: _buildKittyUI(game, state)),
        ),
      ),
    );
  }

  // ── Kitty Exchange ──
  Widget _buildKittyUI(GameService game, MightyGameStateData state) {
    if (!state.isMyTurn) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0D8D4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              L10n.of(context).mtExchangingKitty,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF5A4038)),
            ),
            // Show the declarer's remaining time so others know how long to wait.
            if (_remainingSeconds > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${_remainingSeconds}s',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _remainingSeconds <= 5
                      ? const Color(0xFFE53935)
                      : const Color(0xFF8A7A72),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 4),
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
                for (final suit in ['spade', 'diamond', 'heart', 'club'])
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
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _friendRank = rank;
                        _syncFriendCardSelection(state);
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 44,
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
                clipBehavior: Clip.antiAlias,
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
                child: SingleChildScrollView(
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
              ('diamond', '♦', const Color(0xFF6FB6E5)),
              ('heart', '♥', const Color(0xFFD24B4B)),
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
    if (cards.isEmpty) {
      // After the last card is played, keep the hand panel visible instead of
      // collapsing the whole bottom area (jarring layout jump). Preserve the
      // captured-points chip + prev-trick button and show a "waiting" note
      // while the round finishes.
      final showStrip =
          state.phase == 'playing' ||
          state.phase == 'trick_end' ||
          state.phase == 'round_end';
      return Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
        decoration: const BoxDecoration(
          color: Color(0xEBFFFFFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: Color(0xFFE0D8D4))),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showStrip)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                child: Row(
                  children: [
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child:
                              _buildMyRoleBadge(state, game) ??
                              _buildMyPointCardStrip(state),
                        ),
                      ),
                    ),
                    if (game.hasMightyPrevTrick && state.tricks.isNotEmpty)
                      _buildPrevTrickButton(state),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                L10n.of(context).mtWaiting,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8A7A72),
                ),
              ),
            ),
          ],
        ),
      );
    }

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
          // Non-declarer players wait for the declarer's kitty exchange — show
          // the note above the hand (spectators see it in the centre instead).
          if (state.phase == 'kitty_exchange' && !state.isMyTurn)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE0D8D4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.swap_horiz,
                      size: 16,
                      color: Color(0xFF5A4038),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        L10n.of(context).mtExchangingKitty,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF5A4038),
                        ),
                      ),
                    ),
                    if (_remainingSeconds > 0) ...[
                      const SizedBox(width: 8),
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
                  ],
                ),
              ),
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
              padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
              child: Row(
                children: [
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child:
                            _buildMyRoleBadge(state, game) ??
                            _buildMyPointCardStrip(state),
                      ),
                    ),
                  ),
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
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
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
                            suit: state.currentBid['suit']?.toString() ?? '',
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
              'diamond',
              '\u2666',
              const Color(0xFF6FB6E5),
              enabled: suitAvailable('diamond'),
              onTap: () => selectSuit('diamond'),
            ),
            _buildSuitChip(
              'heart',
              '\u2665',
              const Color(0xFFD24B4B),
              enabled: suitAvailable('heart'),
              onTap: () => selectSuit('heart'),
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
                  SuitIcon(suit: _bidSuit, size: 14, color: Colors.white),
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
    const suits = ['spade', 'diamond', 'heart', 'club'];
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

    // Non-declarer players: show the "declarer is choosing a kill" note above
    // the hand (spectators see it in the centre trick box instead).
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                l10n.mtKillPhaseWait(declarerName),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5A4038),
                ),
              ),
            ),
            if (_remainingSeconds > 0) ...[
              const SizedBox(width: 8),
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
          ],
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
          _buildKillCardChip(ownHand, 'mighty_joker'),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final suit in suits) ...[
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _killSuitTab = suit),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
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
        final cardPadding = cards.length >= 8 ? 1.5 : 3.0;

        // Phone-sized caps: on a browser window the ten-card hand stayed small
        // however much room there was. Grow with the viewport against the same
        // 400pt design width the other boards use, web only.
        final media = MediaQuery.of(context);
        // 1.3, not 1.6 — see the Tichu board: 1.6 made every screen look
        // like a zoomed-in phone rather than a desktop layout.
        final scale = kIsWeb
            ? (media.size.shortestSide / 400).clamp(1.0, 1.3)
            : 1.0;
        final maxCardWidth = 52.0 * scale;

        // One row while the cards can stay full size; two the moment a single
        // line would force them to shrink. The card keeps a 1:1.4 ratio, so
        // narrower cards are also shorter — a hand that has to shrink to fit
        // one line reads worse than the same cards at full size over two.
        //
        // An earlier attempt allowed 60% of full size here, which on any
        // desktop window meant the hand never split at all.
        final oneRowWidth =
            (availableWidth - cards.length * cardPadding * 2) / cards.length;
        final perRow = (cards.length <= 7 || oneRowWidth >= maxCardWidth)
            ? cards.length
            : (cards.length / 2).ceil();
        final totalPadding = perRow * cardPadding * 2;
        var cardWidth = ((availableWidth - totalPadding) / perRow).clamp(
          0.0,
          maxCardWidth,
        );
        var cardHeight = (cardWidth * 1.4).clamp(52.0 * scale, 73.0 * scale);

        // Sizing off width alone lets the hand grow until it covers the table,
        // because a desktop window has width to spare. Bound the rows to a
        // share of the screen and bring the width back with it.
        final rows = perRow >= cards.length ? 1 : 2;
        final maxCardHeight = (media.size.height * 0.26) / rows;
        if (cardHeight > maxCardHeight) {
          cardHeight = maxCardHeight;
          cardWidth = cardHeight / 1.4;
        }

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
          // Mark kitty (바닥) cards whenever we're viewing them during the
          // exchange — including spectators/other players, not just the
          // declarer (isKitty requires it to be my turn).
          final isKittyCard =
              !isMightyCard &&
              !isJokerCallCard &&
              !isFriendCard &&
              state?.phase == 'kitty_exchange' &&
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

        // Single row whenever perRow covers the whole hand. This used to test
        // `cards.length <= 7` on its own, so perRow only ever influenced the
        // card width and the split stayed at seven no matter how much room
        // there was — the two had to agree, or widening the window made the
        // cards bigger and still cut them in half.
        if (perRow >= cards.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: cards.map(buildCard).toList(),
            ),
          );
        }

        final half = perRow;
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
            ('diamond', '\u2666', const Color(0xFF6FB6E5)),
            ('heart', '\u2665', const Color(0xFFD24B4B)),
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
                child: SuitIcon(suit: s.$1, size: 18, color: s.$3),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
            child: Row(
              children: [
                const SizedBox(width: 14),
                const Expanded(child: SizedBox()),
                SizedBox(
                  width: 48,
                  child: Text(
                    L10n.of(context).llRound,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9A8E8A),
                    ),
                  ),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    L10n.of(context).mtTotal,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF9A8E8A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...state.players.map((p) {
            final roundScore = (result?['scores']?[p.id] as num?)?.toInt();
            final totalScore = state.scores[p.id] ?? 0;
            final isDeclarer = p.id == state.declarer;
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
              decoration: BoxDecoration(
                color: p.position == 'self'
                    ? const Color(0xFFF7F1EC)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    child: isDeclarer
                        ? const Text(
                            '\u2605',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF8A00),
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Text(
                      p.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: p.position == 'self'
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: const Color(0xFF5A4038),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    child: Text(
                      roundScore == null ? '' : '$roundScore',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: (roundScore ?? 0) < 0
                            ? const Color(0xFFE53935)
                            : const Color(0xFF3E312A),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '$totalScore',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: totalScore < 0
                            ? const Color(0xFFE53935)
                            : const Color(0xFF3E312A),
                      ),
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
            // Always-allow / always-deny moved to app settings + the
            // eye-icon viewers panel since it's a per-account policy
            // about "my cards", not a per-request choice.
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
  /// Board scale for overlays and dialogs, matching the hand and seats.
  ///
  /// Capped at 1.0 off the web so the app is untouched; on a browser the
  /// panels were drawn at phone sizes in the middle of a large window.
  double get _webScale => kIsWeb
      ? (MediaQuery.of(context).size.shortestSide / 400).clamp(1.0, 1.3)
      : 1.0;

  /// Text/chrome scale: half of _webScale's excess. Growing labels at the same
  /// rate as the cards is what made these panels look oversized on a browser.
  double get _webTextScale => 1 + (_webScale - 1) * 0.5;

  Widget _buildSettingRevealOverlay(
    MightySettingEvent event, {
    String? trumpSuit,
  }) {
    final l10n = L10n.of(context);
    final s = _webScale;
    // Labels grow at half the card rate — see _webTextScale.
    final ts = _webTextScale;
    // SizedBox.expand (not Positioned.fill) so this can be returned from a
    // Consumer placed at the top of the body Stack — above the round-result
    // overlay — without needing to be a direct Stack child.
    return SizedBox.expand(
      child: GestureDetector(
        onTap: () => setState(() {
          _dismissedSettingKey = '${event.round}-${event.playerId}';
        }),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          alignment: Alignment.center,
          child: ConstrainedBox(
            // Without a ceiling the box grows with its widest row, so on a
            // wide window it ran from edge to edge for the sake of one line
            // of cards.
            constraints: BoxConstraints(maxWidth: 460 * s),
            child: Container(
            margin: EdgeInsets.symmetric(horizontal: 16 * s),
            padding: EdgeInsets.fromLTRB(18 * s, 16 * s, 18 * s, 14 * s),
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
                    Icon(
                      Icons.emoji_events,
                      size: 22 * s,
                      color: const Color(0xFFE65100),
                    ),
                    SizedBox(width: 6 * s),
                    Text(
                      l10n.mtSettingRevealTitle,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17 * ts,
                        color: const Color(0xFFE65100),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8 * s),
                Text(
                  l10n.mtSettingRevealBody(event.playerName),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13 * ts,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF5A4038),
                  ),
                ),
                SizedBox(height: 12 * s),
                _buildDealMissCardRows(
                  event.cards,
                  splitAt: 6,
                  trumpSuit: trumpSuit,
                ),
                SizedBox(height: 10 * s),
                Text(
                  l10n.mtSettingTapToClose,
                  style: TextStyle(
                    fontSize: 11 * ts,
                    color: const Color(0xFF8A7A72),
                  ),
                ),
              ],
            ),
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
  Widget _buildDealMissCardRows(
    List<String> cards, {
    int? splitAt = 1,
    String? trumpSuit,
  }) {
    final highlightTrump = trumpSuit != null && trumpSuit != 'no_trump';
    Widget buildRow(List<String> ids) {
      final tiles = <Widget>[];
      for (int i = 0; i < ids.length; i++) {
        if (i > 0) tiles.add(SizedBox(width: 4 * _webScale));
        final id = ids[i];
        Widget card = PlayingCard(
          cardId: _displayCardId(id),
          width: 38 * _webScale,
          height: 54 * _webScale,
          isInteractive: false,
        );
        // Frame trump-suit cards so the 기루다 holdings stand out. Match the
        // PlayingCard corner radius ((w/48*14).clamp(4,14); w=38 → ~11) so the
        // border hugs the rounded card corners instead of cutting inside them.
        if (highlightTrump && _getCardSuit(id) == trumpSuit) {
          card = Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _bidAccentColor(trumpSuit), width: 2.5),
            ),
            child: card,
          );
        }
        tiles.add(card);
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: tiles,
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
      behavior: HitTestBehavior.opaque,
      onTap: inHand ? null : () => setState(() => _selectedKillCard = cardId),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: isJoker ? double.infinity : 52,
        constraints: const BoxConstraints(minHeight: 44),
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
                  // Spelled out, the same way Tichu's history popup does it:
                  // "/50" beside a running total reads as a fraction.
                  Text(
                    L10n.of(context).spectatorTargetScore(game.roomTargetScore),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7A90),
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
        content: state.scoreHistory.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  L10n.of(ctx).gameNoCompletedRounds,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7A90),
                  ),
                ),
              )
            : SizedBox(
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
                        double fontSize = 12,
                        EdgeInsets padding = const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 9,
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
                                size: 12,
                                color: _bidAccentColor(trumpSuit),
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: color,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return Table(
                        columnWidths: {
                          0: const FlexColumnWidth(0.6),
                          1: const FlexColumnWidth(1.5),
                          for (int i = 0; i < state.players.length; i++)
                            i + 2: const FlexColumnWidth(1),
                        },
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(
                            decoration: const BoxDecoration(
                              color: Color(0xFFEAF2FF),
                              border: Border(
                                bottom: BorderSide(
                                  color: Color(0xFFC9DCF7),
                                  width: 1,
                                ),
                              ),
                            ),
                            children: [
                              cell(
                                'R',
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: const Color(0xFF295EA8),
                              ),
                              cell(
                                L10n.of(context).mtBidShort,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: const Color(0xFF295EA8),
                              ),
                              ...state.players.map(
                                (p) => cell(
                                  p.name.length > 4
                                      ? p.name.substring(0, 4)
                                      : p.name,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: p.position == 'self'
                                      ? const Color(0xFF355D89)
                                      : const Color(0xFF295EA8),
                                ),
                              ),
                            ],
                          ),
                          ...state.scoreHistory.asMap().entries.map((mapEntry) {
                            final rowIndex = mapEntry.key;
                            final entry = mapEntry.value;
                            final trump =
                                suitSymbol[entry.trumpSuit] ??
                                entry.trumpSuit ??
                                '?';
                            for (final p in state.players) {
                              cumulativeScores[p.id] =
                                  (cumulativeScores[p.id] ?? 0) +
                                  (entry.scores[p.id] ?? 0);
                            }
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
                            // Colour the bid cell by outcome so a scan of the column
                            // reads success (green) / fail (red) / deal-miss (amber).
                            final bidColor = entry.dealMiss
                                ? const Color(0xFFB56A1D)
                                : entry.success
                                ? const Color(0xFF2E9E5B)
                                : const Color(0xFFD04A5B);
                            return TableRow(
                              decoration: BoxDecoration(
                                color: rowIndex.isOdd
                                    ? const Color(0xFFF4F8FD)
                                    : null,
                              ),
                              children: [
                                cell(
                                  '${entry.round}',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: const Color(0xFF8A92A0),
                                ),
                                bidCell(
                                  trumpSuit: showSuitIcon ? trumpKey : null,
                                  label: bidLabel,
                                  color: bidColor,
                                  dealMiss: entry.dealMiss,
                                ),
                                ...state.players.map((p) {
                                  final diff = entry.scores[p.id] ?? 0;
                                  // For the declarer on a successful round, split
                                  // off the deal-miss pool bonus so the user can
                                  // tell the round's "raw" score from the leftover
                                  // pool payout — explains the (48 + 5) = 53 case.
                                  final isDeclarer = p.id == entry.declarer;
                                  final bonus = isDeclarer && entry.success
                                      ? entry.dealMissBonus
                                      : 0;
                                  final base = diff - bonus;
                                  final scoreColor = diff < 0
                                      ? const Color(0xFFD04A5B)
                                      : const Color(0xFF233142);
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 6,
                                    ),
                                    child: bonus > 0
                                        ? Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                '$base',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      p.position == 'self'
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                  color: scoreColor,
                                                  height: 1.1,
                                                ),
                                              ),
                                              Text(
                                                '+$bonus',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: Color(0xFFB56A1D),
                                                  height: 1.1,
                                                ),
                                              ),
                                            ],
                                          )
                                        : Text(
                                            '$diff',
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: p.position == 'self'
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              color: scoreColor,
                                              height: 1.2,
                                            ),
                                          ),
                                  );
                                }),
                              ],
                            );
                          }),
                          TableRow(
                            decoration: const BoxDecoration(
                              color: Color(0xFFEAF2FF),
                              border: Border(
                                top: BorderSide(
                                  color: Color(0xFFC9DCF7),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            children: [
                              cell('', fontWeight: FontWeight.w800),
                              cell(
                                L10n.of(context).mtTotal,
                                align: TextAlign.left,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: const Color(0xFF233142),
                              ),
                              ...state.players.map((p) {
                                final total = cumulativeScores[p.id] ?? 0;
                                return cell(
                                  '$total',
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  color: total < 0
                                      ? const Color(0xFFD04A5B)
                                      : const Color(0xFF233142),
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
    showPlayerProfileDialog(
      context,
      nickname,
      game,
      initialGame: 'mighty',
      subtitle: L10n.of(context).gamePlayerProfile,
      isBot: isBot,
      dismissWhen: (g) =>
          g.mightyGameState == null || g.mightyGameState!.phase == 'game_end',
      placeholderBackground: const Color(0xFFE8F5E9),
      placeholderForeground: const Color(0xFF2E7D32),
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
