class LLPlayer {
  final String id;
  final String name;
  final String position;
  final int cardCount;
  final int tokens;
  final bool eliminated;
  final bool protected;
  final List<String> discardPile;
  final int timeoutCount;
  final List<String> cards;
  final bool canViewCards;
  final bool connected;

  LLPlayer({
    required this.id,
    required this.name,
    this.position = '',
    this.cardCount = 0,
    this.tokens = 0,
    this.eliminated = false,
    this.protected = false,
    this.discardPile = const [],
    this.timeoutCount = 0,
    this.cards = const [],
    this.canViewCards = false,
    this.connected = true,
  });

  factory LLPlayer.fromJson(Map<String, dynamic> json) {
    return LLPlayer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      position: json['position'] ?? '',
      cardCount: json['cardCount'] ?? 0,
      tokens: json['tokens'] ?? 0,
      eliminated: json['eliminated'] == true,
      protected: json['protected'] == true,
      discardPile: List<String>.from(json['discardPile'] ?? const []),
      timeoutCount: json['timeoutCount'] ?? 0,
      cards: List<String>.from(json['cards'] ?? const []),
      canViewCards: json['canViewCards'] == true,
      connected: json['connected'] != false,
    );
  }
}

class LLPendingEffect {
  final String type;
  final String playerId;
  final String? targetId;
  final bool needsTarget;
  final bool needsGuess;
  final List<String> validTargets;
  final bool resolved;
  final String? guess;
  final Map<String, dynamic>? result;

  LLPendingEffect({
    required this.type,
    required this.playerId,
    this.targetId,
    this.needsTarget = false,
    this.needsGuess = false,
    this.validTargets = const [],
    this.resolved = false,
    this.guess,
    this.result,
  });

  factory LLPendingEffect.fromJson(Map<String, dynamic> json) {
    return LLPendingEffect(
      type: json['type'] ?? '',
      playerId: json['playerId'] ?? '',
      targetId: json['targetId'] as String?,
      needsTarget: json['needsTarget'] == true,
      needsGuess: json['needsGuess'] == true,
      validTargets: List<String>.from(json['validTargets'] ?? const []),
      resolved: json['resolved'] == true,
      guess: json['guess'] as String?,
      result: json['result'] != null
          ? Map<String, dynamic>.from(json['result'])
          : null,
    );
  }
}

class LLRoundHistory {
  final int round;
  final String? winner;
  final String? winnerName;
  final Map<String, String?> finalHands;

  LLRoundHistory({
    required this.round,
    this.winner,
    this.winnerName,
    this.finalHands = const {},
  });

  factory LLRoundHistory.fromJson(Map<String, dynamic> json) {
    Map<String, String?> hands = {};
    if (json['finalHands'] != null) {
      (json['finalHands'] as Map).forEach((k, v) {
        hands[k.toString()] = v as String?;
      });
    }
    return LLRoundHistory(
      round: json['round'] ?? 0,
      winner: json['winner'] as String?,
      winnerName: json['winnerName'] as String?,
      finalHands: hands,
    );
  }
}

class LLGameStateData {
  final String phase;
  final int round;
  final List<LLPlayer> players;
  final List<String> myCards;
  final String? currentPlayer;
  final bool isMyTurn;
  final int drawPileCount;
  final List<String> faceUpCards;
  final LLPendingEffect? pendingEffect;
  final Map<String, int> tokens;
  final int targetTokens;
  final List<LLRoundHistory> roundHistory;
  final List<String> guessableCards;
  final int? turnDeadline;

  LLGameStateData({
    this.phase = '',
    this.round = 0,
    this.players = const [],
    this.myCards = const [],
    this.currentPlayer,
    this.isMyTurn = false,
    this.drawPileCount = 0,
    this.faceUpCards = const [],
    this.pendingEffect,
    this.tokens = const {},
    this.targetTokens = 3,
    this.roundHistory = const [],
    this.guessableCards = const [],
    this.turnDeadline,
  });

  factory LLGameStateData.fromJson(Map<String, dynamic> json) {
    List<LLPlayer> playerList = [];
    if (json['players'] != null) {
      playerList =
          (json['players'] as List).map((p) => LLPlayer.fromJson(p)).toList();
    }

    LLPendingEffect? pending;
    if (json['pendingEffect'] != null) {
      pending = LLPendingEffect.fromJson(json['pendingEffect']);
    }

    Map<String, int> tokenMap = {};
    if (json['tokens'] != null) {
      (json['tokens'] as Map).forEach((k, v) {
        tokenMap[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    List<LLRoundHistory> history = [];
    if (json['roundHistory'] != null) {
      history = (json['roundHistory'] as List)
          .map((e) => LLRoundHistory.fromJson(e))
          .toList();
    }

    return LLGameStateData(
      phase: json['phase'] ?? '',
      round: json['round'] ?? 0,
      players: playerList,
      myCards: List<String>.from(json['myCards'] ?? []),
      currentPlayer: json['currentPlayer'],
      isMyTurn: json['isMyTurn'] ?? false,
      drawPileCount: json['drawPileCount'] ?? 0,
      faceUpCards: List<String>.from(json['faceUpCards'] ?? []),
      pendingEffect: pending,
      tokens: tokenMap,
      targetTokens: json['targetTokens'] ?? 3,
      roundHistory: history,
      guessableCards: List<String>.from(json['guessableCards'] ?? []),
      turnDeadline: json['turnDeadline'] as int?,
    );
  }
}
