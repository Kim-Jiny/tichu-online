import 'player.dart';

class Room {
  final String id;
  final String name;
  final List<Player> players;
  final int playerCount;
  final int spectatorCount;
  final bool isPlaying;
  final bool isPrivate;
  final bool isRanked;
  final bool gameInProgress;
  final int turnTimeLimit;
  final int targetScore;
  final String gameType;
  final int maxPlayers;
  /// Enabled Skull King expansions — only meaningful when [gameType] is
  /// `skull_king`. Subset of `['kraken', 'white_whale', 'loot']`.
  final List<String> skExpansions;

  Room({
    required this.id,
    required this.name,
    this.players = const [],
    this.playerCount = 0,
    this.spectatorCount = 0,
    this.isPlaying = false,
    this.isPrivate = false,
    this.isRanked = false,
    this.gameInProgress = false,
    this.turnTimeLimit = 30,
    this.targetScore = 1000,
    this.gameType = 'tichu',
    this.maxPlayers = 4,
    this.skExpansions = const [],
  });

  bool get isSkullKing => gameType == 'skull_king';

  factory Room.fromJson(Map<String, dynamic> json) {
    List<Player> playerList = [];
    if (json['players'] != null) {
      playerList = (json['players'] as List)
          .map((p) => Player.fromJson(p))
          .toList();
    }

    List<String> expansions = const [];
    if (json['skExpansions'] is List) {
      expansions = (json['skExpansions'] as List)
          .whereType<String>()
          .toList(growable: false);
    }

    return Room(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      players: playerList,
      playerCount: json['playerCount'] ?? playerList.length,
      spectatorCount: json['spectatorCount'] ?? 0,
      isPlaying: json['isPlaying'] ?? false,
      isPrivate: json['isPrivate'] ?? false,
      isRanked: json['isRanked'] ?? false,
      gameInProgress: json['gameInProgress'] ?? false,
      turnTimeLimit: json['turnTimeLimit'] ?? 30,
      targetScore: json['targetScore'] ?? 1000,
      gameType: json['gameType'] ?? 'tichu',
      maxPlayers: json['maxPlayers'] ?? 4,
      skExpansions: expansions,
    );
  }
}
