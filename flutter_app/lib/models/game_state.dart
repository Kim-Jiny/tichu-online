import 'player.dart';

class TrickPlay {
  final String playerId;
  final String playerName;
  final List<String> cards;
  final String combo;

  TrickPlay({
    required this.playerId,
    required this.playerName,
    required this.cards,
    required this.combo,
  });

  factory TrickPlay.fromJson(Map<String, dynamic> json) {
    return TrickPlay(
      playerId: json['playerId'] ?? '',
      playerName: json['playerName'] ?? '',
      cards: List<String>.from(json['cards'] ?? []),
      combo: json['combo'] ?? '',
    );
  }
}

class GameStateData {
  final String phase;
  final List<Player> players;
  final List<String> myCards;
  final String? currentPlayer;
  final bool isMyTurn;
  final List<TrickPlay> currentTrick;
  final Map<String, int> totalScores;
  final Map<String, int> lastRoundScores;
  final String? callRank;
  final bool needsToCallRank;
  final bool dragonPending;
  final bool exchangeDone;
  final Map<String, String>? receivedFrom; // { left: cardId, partner: cardId, right: cardId }
  final bool largeTichuResponded;
  final bool canDeclareSmallTichu;
  final int? turnDeadline; // epoch ms

  GameStateData({
    this.phase = '',
    this.players = const [],
    this.myCards = const [],
    this.currentPlayer,
    this.isMyTurn = false,
    this.currentTrick = const [],
    this.totalScores = const {'teamA': 0, 'teamB': 0},
    this.lastRoundScores = const {},
    this.callRank,
    this.needsToCallRank = false,
    this.dragonPending = false,
    this.exchangeDone = false,
    this.receivedFrom,
    this.largeTichuResponded = false,
    this.canDeclareSmallTichu = false,
    this.turnDeadline,
  });

  factory GameStateData.fromJson(Map<String, dynamic> json) {
    List<Player> playerList = [];
    if (json['players'] != null) {
      playerList = (json['players'] as List)
          .map((p) => Player.fromJson(p))
          .toList();
    }

    List<TrickPlay> trickList = [];
    if (json['currentTrick'] != null) {
      trickList = (json['currentTrick'] as List)
          .map((t) => TrickPlay.fromJson(t))
          .toList();
    }

    Map<String, int> scores = {'teamA': 0, 'teamB': 0};
    if (json['totalScores'] != null) {
      scores = {
        'teamA': json['totalScores']['teamA'] ?? 0,
        'teamB': json['totalScores']['teamB'] ?? 0,
      };
    }

    Map<String, int> lastScores = {};
    if (json['lastRoundScores'] != null) {
      lastScores = {
        'teamA': json['lastRoundScores']['teamA'] ?? 0,
        'teamB': json['lastRoundScores']['teamB'] ?? 0,
      };
    }

    return GameStateData(
      phase: json['phase'] ?? '',
      players: playerList,
      myCards: List<String>.from(json['myCards'] ?? []),
      currentPlayer: json['currentPlayer'],
      isMyTurn: json['isMyTurn'] ?? false,
      currentTrick: trickList,
      totalScores: scores,
      lastRoundScores: lastScores,
      callRank: json['callRank'],
      needsToCallRank: json['needsToCallRank'] ?? false,
      dragonPending: json['dragonPending'] ?? false,
      exchangeDone: json['exchangeDone'] ?? false,
      receivedFrom: json['receivedFrom'] != null
          ? Map<String, String>.from(json['receivedFrom'])
          : null,
      largeTichuResponded: json['largeTichuResponded'] ?? false,
      canDeclareSmallTichu: json['canDeclareSmallTichu'] ?? false,
      turnDeadline: json['turnDeadline'] as int?,
    );
  }
}
