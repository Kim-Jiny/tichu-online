class SKPlayer {
  final String id;
  final String name;
  final String position;
  final int cardCount;
  final int? bid;
  final int tricks;
  final int totalScore;
  final bool hasBid;
  final int timeoutCount;
  final List<String> cards;
  final bool canViewCards;
  final bool connected;

  SKPlayer({
    required this.id,
    required this.name,
    this.position = '',
    this.cardCount = 0,
    this.bid,
    this.tricks = 0,
    this.totalScore = 0,
    this.hasBid = false,
    this.timeoutCount = 0,
    this.cards = const [],
    this.canViewCards = false,
    this.connected = true,
  });

  factory SKPlayer.fromJson(Map<String, dynamic> json) {
    return SKPlayer(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      position: json['position'] ?? '',
      cardCount: json['cardCount'] ?? 0,
      bid: json['bid'] as int?,
      tricks: json['tricks'] ?? 0,
      totalScore: json['totalScore'] ?? 0,
      hasBid: json['hasBid'] ?? false,
      timeoutCount: json['timeoutCount'] ?? 0,
      cards: List<String>.from(json['cards'] ?? const []),
      canViewCards: json['canViewCards'] == true,
      connected: json['connected'] != false,
    );
  }
}

class SKTrickPlay {
  final String playerId;
  final String playerName;
  final String cardId;
  final String? tigressChoice;

  SKTrickPlay({
    required this.playerId,
    required this.playerName,
    required this.cardId,
    this.tigressChoice,
  });

  factory SKTrickPlay.fromJson(Map<String, dynamic> json) {
    return SKTrickPlay(
      playerId: json['playerId'] ?? '',
      playerName: json['playerName'] ?? '',
      cardId: json['cardId'] ?? '',
      tigressChoice: json['tigressChoice'] as String?,
    );
  }
}

class SKGameStateData {
  final String phase;
  final int round;
  final int totalRounds;
  final int trickNumber;
  final List<SKPlayer> players;
  final List<String> myCards;
  final String? currentPlayer;
  final bool isMyTurn;
  final List<SKTrickPlay> currentTrick;
  final List<String> legalCards;
  final Map<String, int> totalScores;
  final Map<String, int> lastRoundScores;
  final List<Map<String, dynamic>> scoreHistory;
  final String? lastTrickWinner;
  final int lastTrickBonus;
  final List<Map<String, dynamic>> lastTrickBonusDetail;
  final String? trickStarter;
  final String? roundStarter;
  final int? turnDeadline;

  SKGameStateData({
    this.phase = '',
    this.round = 0,
    this.totalRounds = 10,
    this.trickNumber = 0,
    this.players = const [],
    this.myCards = const [],
    this.currentPlayer,
    this.isMyTurn = false,
    this.currentTrick = const [],
    this.legalCards = const [],
    this.totalScores = const {},
    this.lastRoundScores = const {},
    this.scoreHistory = const [],
    this.lastTrickWinner,
    this.lastTrickBonus = 0,
    this.lastTrickBonusDetail = const [],
    this.trickStarter,
    this.roundStarter,
    this.turnDeadline,
  });

  factory SKGameStateData.fromJson(Map<String, dynamic> json) {
    List<SKPlayer> playerList = [];
    if (json['players'] != null) {
      playerList = (json['players'] as List)
          .map((p) => SKPlayer.fromJson(p))
          .toList();
    }

    List<SKTrickPlay> trickList = [];
    if (json['currentTrick'] != null) {
      trickList = (json['currentTrick'] as List)
          .map((t) => SKTrickPlay.fromJson(t))
          .toList();
    }

    Map<String, int> scores = {};
    if (json['totalScores'] != null) {
      (json['totalScores'] as Map).forEach((k, v) {
        scores[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    Map<String, int> lastScores = {};
    if (json['lastRoundScores'] != null) {
      (json['lastRoundScores'] as Map).forEach((k, v) {
        lastScores[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
    }

    List<Map<String, dynamic>> history = [];
    if (json['scoreHistory'] != null) {
      history = (json['scoreHistory'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    List<Map<String, dynamic>> bonusDetail = [];
    if (json['lastTrickBonusDetail'] != null) {
      bonusDetail = (json['lastTrickBonusDetail'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }

    return SKGameStateData(
      phase: json['phase'] ?? '',
      round: json['round'] ?? 0,
      totalRounds: json['totalRounds'] ?? 10,
      trickNumber: json['trickNumber'] ?? 0,
      players: playerList,
      myCards: List<String>.from(json['myCards'] ?? []),
      currentPlayer: json['currentPlayer'],
      isMyTurn: json['isMyTurn'] ?? false,
      currentTrick: trickList,
      legalCards: List<String>.from(json['legalCards'] ?? []),
      totalScores: scores,
      lastRoundScores: lastScores,
      scoreHistory: history,
      lastTrickWinner: json['lastTrickWinner'],
      lastTrickBonus: json['lastTrickBonus'] ?? 0,
      lastTrickBonusDetail: bonusDetail,
      trickStarter: json['trickStarter'],
      roundStarter: json['roundStarter'],
      turnDeadline: json['turnDeadline'] as int?,
    );
  }
}
