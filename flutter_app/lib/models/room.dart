import 'player.dart';

class Room {
  final String id;
  final String name;
  final List<Player> players;
  final int playerCount;
  final bool isPlaying;

  Room({
    required this.id,
    required this.name,
    this.players = const [],
    this.playerCount = 0,
    this.isPlaying = false,
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
      isPlaying: json['isPlaying'] ?? false,
    );
  }
}
