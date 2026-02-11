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
  });

  factory Room.fromJson(Map<String, dynamic> json) {
    List<Player> playerList = [];
    if (json['players'] != null) {
      playerList = (json['players'] as List)
          .map((p) => Player.fromJson(p))
          .toList();
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
    );
  }
}
