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
  final int? turnDeadline;
  final bool kittyReceived;
  final List<MightyTrickPlay> lastTrickCards;
  final String? lastTrickWinner;

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
    this.turnDeadline,
    this.kittyReceived = false,
    this.lastTrickCards = const [],
    this.lastTrickWinner,
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
      turnDeadline: (json['turnDeadline'] as num?)?.toInt(),
      kittyReceived: json['kittyReceived'] == true,
      lastTrickCards: lastTrickList,
      lastTrickWinner: json['lastTrickWinner'],
    );
  }
}
