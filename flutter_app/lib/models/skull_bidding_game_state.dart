class SkullBiddingPlayer {
  final String id;
  final String name;
  final String position;
  final int poolRemaining;
  final int handCount;
  final int stackCount;
  final int successCount;
  final bool eliminated;

  // Spliced in server-side (decorateSeats) — the engine itself never knew
  // these, same as every other game's player model here.
  final bool connected;
  final int timeoutCount;
  final String? photoUrl;
  final bool isBot;

  SkullBiddingPlayer({
    required this.id,
    required this.name,
    this.position = '',
    this.poolRemaining = 0,
    this.handCount = 0,
    this.stackCount = 0,
    this.successCount = 0,
    this.eliminated = false,
    this.connected = true,
    this.timeoutCount = 0,
    this.photoUrl,
    this.isBot = false,
  });

  factory SkullBiddingPlayer.fromJson(Map<String, dynamic> json) {
    return SkullBiddingPlayer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      position: json['position'] ?? '',
      poolRemaining: json['poolRemaining'] ?? 0,
      handCount: json['handCount'] ?? 0,
      stackCount: json['stackCount'] ?? 0,
      successCount: json['successCount'] ?? 0,
      eliminated: json['eliminated'] == true,
      connected: json['connected'] != false,
      timeoutCount: json['timeoutCount'] ?? 0,
      photoUrl: json['photoUrl'] as String?,
      isBot: json['isBot'] == true,
    );
  }
}

/// One entry in the public reveal log for the current/most recent challenge
/// — who flipped, and what came up. Cleared at the start of the next round
/// (see SkullBiddingGame._startNextRound).
class SkullBiddingRevealEntry {
  final String playerId;
  final String disc; // 'rose' | 'skull'

  SkullBiddingRevealEntry({required this.playerId, required this.disc});

  factory SkullBiddingRevealEntry.fromJson(Map<String, dynamic> json) {
    return SkullBiddingRevealEntry(
      playerId: json['playerId'] ?? '',
      disc: json['disc'] ?? '',
    );
  }
}

class SkullBiddingRoundHistoryEntry {
  final int round;
  final String? challengerId;
  final int bid;
  final int tableTotal;
  final String result; // 'success' | 'fail'

  SkullBiddingRoundHistoryEntry({
    required this.round,
    this.challengerId,
    this.bid = 0,
    this.tableTotal = 0,
    this.result = '',
  });

  factory SkullBiddingRoundHistoryEntry.fromJson(Map<String, dynamic> json) {
    return SkullBiddingRoundHistoryEntry(
      round: json['round'] ?? 0,
      challengerId: json['challengerId'] as String?,
      bid: json['bid'] ?? 0,
      tableTotal: json['tableTotal'] ?? 0,
      result: json['result'] ?? '',
    );
  }
}

class SkullBiddingGameStateData {
  final String phase; // placing | bidding | revealing | round_end | game_end
  final int round;
  final List<SkullBiddingPlayer> players;

  /// Only ever populated with the viewer's own hand — {roses, hasSkull}.
  final int myRoses;
  final bool myHasSkull;

  final String? currentPlayer;
  final bool isMyTurn;

  final int highestBid;
  final String? highestBidder;
  final int? tableTotal;
  final List<String> biddingQueue;

  final String? challengerId;
  final int? targetFlips;
  final int flippedCount;
  final List<SkullBiddingRevealEntry> revealLog;

  /// Set while the challenger who just failed still owes a discard choice.
  final String? pendingDiscardPlayerId;

  final int targetSuccesses;
  final String? gameWinner;
  final List<SkullBiddingRoundHistoryEntry> roundHistory;
  final int? turnDeadline;

  SkullBiddingGameStateData({
    this.phase = '',
    this.round = 0,
    this.players = const [],
    this.myRoses = 0,
    this.myHasSkull = false,
    this.currentPlayer,
    this.isMyTurn = false,
    this.highestBid = 0,
    this.highestBidder,
    this.tableTotal,
    this.biddingQueue = const [],
    this.challengerId,
    this.targetFlips,
    this.flippedCount = 0,
    this.revealLog = const [],
    this.pendingDiscardPlayerId,
    this.targetSuccesses = 2,
    this.gameWinner,
    this.roundHistory = const [],
    this.turnDeadline,
  });

  factory SkullBiddingGameStateData.fromJson(Map<String, dynamic> json) {
    final players = json['players'] != null
        ? (json['players'] as List)
            .map((p) => SkullBiddingPlayer.fromJson(p))
            .toList()
        : <SkullBiddingPlayer>[];

    final hand = json['myHand'] as Map<String, dynamic>?;

    final revealLog = json['revealLog'] != null
        ? (json['revealLog'] as List)
            .map((e) => SkullBiddingRevealEntry.fromJson(e))
            .toList()
        : <SkullBiddingRevealEntry>[];

    final history = json['roundHistory'] != null
        ? (json['roundHistory'] as List)
            .map((e) => SkullBiddingRoundHistoryEntry.fromJson(e))
            .toList()
        : <SkullBiddingRoundHistoryEntry>[];

    final pendingDiscard = json['pendingDiscard'] as Map<String, dynamic>?;

    return SkullBiddingGameStateData(
      phase: json['phase'] ?? '',
      round: json['round'] ?? 0,
      players: players,
      myRoses: hand?['roses'] ?? 0,
      myHasSkull: hand?['hasSkull'] == true,
      currentPlayer: json['currentPlayer'] as String?,
      isMyTurn: json['isMyTurn'] == true,
      highestBid: json['highestBid'] ?? 0,
      highestBidder: json['highestBidder'] as String?,
      tableTotal: json['tableTotal'] as int?,
      biddingQueue: List<String>.from(json['biddingQueue'] ?? const []),
      challengerId: json['challengerId'] as String?,
      targetFlips: json['targetFlips'] as int?,
      flippedCount: json['flippedCount'] ?? 0,
      revealLog: revealLog,
      pendingDiscardPlayerId: pendingDiscard?['playerId'] as String?,
      targetSuccesses: json['targetSuccesses'] ?? 2,
      gameWinner: json['gameWinner'] as String?,
      roundHistory: history,
      turnDeadline: json['turnDeadline'] as int?,
    );
  }
}
