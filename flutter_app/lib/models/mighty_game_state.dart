class MightyPlayer {
  final String id;
  final String name;
  final String position;
  final int cardCount;
  final dynamic bid; // null, 'pass', or Map {points, suit}
  final int trickCount;
  final int pointCount;
  final List<String> pointCards;
  final bool connected;
  final int timeoutCount;
  final List<String> cards;
  final bool canViewCards;

  MightyPlayer({
    required this.id,
    required this.name,
    this.position = '',
    this.cardCount = 0,
    this.bid,
    this.trickCount = 0,
    this.pointCount = 0,
    this.pointCards = const [],
    this.connected = true,
    this.timeoutCount = 0,
    this.cards = const [],
    this.canViewCards = false,
  });

  factory MightyPlayer.fromJson(Map<String, dynamic> json) {
    return MightyPlayer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      position: json['position'] ?? '',
      cardCount: json['cardCount'] ?? 0,
      bid: json['bid'],
      trickCount: json['trickCount'] ?? 0,
      pointCount: json['pointCount'] ?? 0,
      pointCards: List<String>.from(json['pointCards'] ?? const []),
      connected: json['connected'] != false,
      timeoutCount: json['timeoutCount'] ?? 0,
      cards: List<String>.from(json['cards'] ?? const []),
      canViewCards: json['canViewCards'] == true,
    );
  }
}

class MightyTrickPlay {
  final String playerId;
  final String playerName;
  final String cardId;

  MightyTrickPlay({
    required this.playerId,
    required this.playerName,
    required this.cardId,
  });

  factory MightyTrickPlay.fromJson(Map<String, dynamic> json) {
    return MightyTrickPlay(
      playerId: json['playerId'] ?? '',
      playerName: json['playerName'] ?? '',
      cardId: json['cardId'] ?? '',
    );
  }
}

class MightyCompletedTrick {
  final String leader;
  final String winner;
  final List<MightyTrickPlay> cards;

  MightyCompletedTrick({
    required this.leader,
    required this.winner,
    required this.cards,
  });

  factory MightyCompletedTrick.fromJson(Map<String, dynamic> json) {
    return MightyCompletedTrick(
      leader: json['leader'] ?? '',
      winner: json['winner'] ?? '',
      cards: (json['cards'] as List?)
              ?.map((c) => MightyTrickPlay.fromJson(c))
              .toList() ??
          [],
    );
  }
}

class MightyScoreHistoryEntry {
  final int round;
  final int bid;
  final String? trumpSuit;
  final String? declarer;
  final String? partner;
  final bool success;
  final int declarerPoints;
  final Map<String, int> scores;

  MightyScoreHistoryEntry({
    required this.round,
    required this.bid,
    this.trumpSuit,
    this.declarer,
    this.partner,
    required this.success,
    required this.declarerPoints,
    required this.scores,
  });

  factory MightyScoreHistoryEntry.fromJson(Map<String, dynamic> json) {
    final Map<String, int> scores = {};
    if (json['scores'] != null) {
      (json['scores'] as Map).forEach((k, v) {
        scores[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }
    return MightyScoreHistoryEntry(
      round: json['round'] ?? 0,
      bid: json['bid'] ?? 0,
      trumpSuit: json['trumpSuit'],
      declarer: json['declarer'],
      partner: json['partner'],
      success: json['success'] == true,
      declarerPoints: (json['declarerPoints'] as num?)?.toInt() ?? 0,
      scores: scores,
    );
  }
}

class MightyGameStateData {
  final String phase;
  final int round;
  final List<MightyPlayer> players;
  final List<String> myCards;
  final String? currentPlayer;
  final bool isMyTurn;
  final List<MightyTrickPlay> currentTrick;
  final List<String> legalCards;
  final String? trumpSuit;
  final String? declarer;
  final String? friendCard;
  final bool friendRevealed;
  final String? partner;
  final Map<String, dynamic> currentBid;
  final Map<String, dynamic> bids;
  final Map<String, int> scores;
  final Map<String, dynamic>? roundResult;
  final String? mightyCard;
  final String? jokerCallCard;
  final bool jokerCallActive;
  final int? turnDeadline;
  final bool kittyReceived;
  final List<String> kittyCards;
  final List<MightyTrickPlay> lastTrickCards;
  final String? lastTrickWinner;
  final List<MightyCompletedTrick> tricks;
  final List<MightyScoreHistoryEntry> scoreHistory;
  final Map<String, dynamic>? remainingTrumps;

  MightyGameStateData({
    this.phase = '',
    this.round = 0,
    this.players = const [],
    this.myCards = const [],
    this.currentPlayer,
    this.isMyTurn = false,
    this.currentTrick = const [],
    this.legalCards = const [],
    this.trumpSuit,
    this.declarer,
    this.friendCard,
    this.friendRevealed = false,
    this.partner,
    this.currentBid = const {},
    this.bids = const {},
    this.scores = const {},
    this.roundResult,
    this.mightyCard,
    this.jokerCallCard,
    this.jokerCallActive = false,
    this.turnDeadline,
    this.kittyReceived = false,
    this.kittyCards = const [],
    this.lastTrickCards = const [],
    this.lastTrickWinner,
    this.tricks = const [],
    this.scoreHistory = const [],
    this.remainingTrumps,
  });

  factory MightyGameStateData.fromJson(Map<String, dynamic> json) {
    List<MightyPlayer> playerList = [];
    if (json['players'] != null) {
      playerList = (json['players'] as List)
          .map((p) => MightyPlayer.fromJson(p))
          .toList();
    }

    List<MightyTrickPlay> trickList = [];
    if (json['currentTrick'] != null) {
      trickList = (json['currentTrick'] as List)
          .map((t) => MightyTrickPlay.fromJson(t))
          .toList();
    }

    Map<String, int> scores = {};
    if (json['scores'] != null) {
      (json['scores'] as Map).forEach((k, v) {
        scores[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    Map<String, dynamic> currentBid = {};
    if (json['currentBid'] != null) {
      currentBid = Map<String, dynamic>.from(json['currentBid']);
    }

    Map<String, dynamic> bids = {};
    if (json['bids'] != null) {
      (json['bids'] as Map).forEach((k, v) {
        bids[k.toString()] = v;
      });
    }

    Map<String, dynamic>? roundResult;
    if (json['roundResult'] != null) {
      roundResult = Map<String, dynamic>.from(json['roundResult']);
    }

    List<MightyTrickPlay> lastTrickList = [];
    if (json['lastTrickCards'] != null) {
      lastTrickList = (json['lastTrickCards'] as List)
          .map((t) => MightyTrickPlay.fromJson(t))
          .toList();
    }

    return MightyGameStateData(
      phase: json['phase'] ?? '',
      round: json['round'] ?? 0,
      players: playerList,
      myCards: List<String>.from(json['myCards'] ?? []),
      currentPlayer: json['currentPlayer'],
      isMyTurn: json['isMyTurn'] ?? false,
      currentTrick: trickList,
      legalCards: List<String>.from(json['legalCards'] ?? []),
      trumpSuit: json['trumpSuit'],
      declarer: json['declarer'],
      friendCard: json['friendCard'],
      friendRevealed: json['friendRevealed'] == true,
      partner: json['partner'],
      currentBid: currentBid,
      bids: bids,
      scores: scores,
      roundResult: roundResult,
      mightyCard: json['mightyCard'],
      jokerCallCard: json['jokerCallCard'],
      jokerCallActive: json['jokerCallActive'] == true,
      turnDeadline: (json['turnDeadline'] as num?)?.toInt(),
      kittyReceived: json['kittyReceived'] == true,
      kittyCards: List<String>.from(json['kittyCards'] ?? []),
      lastTrickCards: lastTrickList,
      lastTrickWinner: json['lastTrickWinner'],
      tricks: (json['tricks'] as List?)
              ?.map((t) => MightyCompletedTrick.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      scoreHistory: (json['scoreHistory'] as List?)
              ?.map((e) => MightyScoreHistoryEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      remainingTrumps: json['remainingTrumps'] != null
          ? Map<String, dynamic>.from(json['remainingTrumps'])
          : null,
    );
  }
}
