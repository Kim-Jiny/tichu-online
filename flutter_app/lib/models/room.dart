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

  /// Host may forbid spectating entirely; the list hides its spectate button.
  final bool allowSpectators;
  final bool gameInProgress;
  final int turnTimeLimit;
  final int targetScore;
  final String gameType;
  final int maxPlayers;
  /// Effective max players after host has blocked some empty slots.
  /// Equal to [maxPlayers] minus the number of blocked slots.
  final int effectiveMaxPlayers;
  /// Enabled Skull King expansions — only meaningful when [gameType] is
  /// `skull_king`. Subset of `['kraken', 'white_whale', 'loot']`.
  final List<String> skExpansions;
  /// Tichu-only: host opted to randomize teams at game start instead of
  /// using the fixed (0,2) vs (1,3) seat-to-team mapping. Mirrors SK/Mighty
  /// free-seat UX.
  final bool randomSeating;

  /// Host allows a spectator to take over a bot seat in a running match, and
  /// a seated player to hand their seat to a bot and walk. Never true for
  /// ranked rooms (they hold no bots) or rooms with spectating off.
  final bool allowMidGameJoin;

  /// Seats a bot currently holds. A mid-game-join room is only actually
  /// enterable while this is above zero.
  final int botSeatCount;

  /// Whether the spectate view should offer the break-in button at all.
  bool get canJoinInProgress =>
      allowMidGameJoin && gameInProgress && botSeatCount > 0;

  Room({
    required this.id,
    required this.name,
    this.players = const [],
    this.playerCount = 0,
    this.spectatorCount = 0,
    this.isPlaying = false,
    this.isPrivate = false,
    this.isRanked = false,
    this.allowSpectators = true,
    this.gameInProgress = false,
    this.turnTimeLimit = 30,
    this.targetScore = 1000,
    this.gameType = 'tichu',
    this.maxPlayers = 4,
    int? effectiveMaxPlayers,
    this.skExpansions = const [],
    this.randomSeating = false,
    this.allowMidGameJoin = false,
    this.botSeatCount = 0,
  }) : effectiveMaxPlayers = effectiveMaxPlayers ?? maxPlayers;

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
      allowSpectators: json['allowSpectators'] ?? true,
      gameInProgress: json['gameInProgress'] ?? false,
      turnTimeLimit: json['turnTimeLimit'] ?? 30,
      targetScore: json['targetScore'] ?? 1000,
      gameType: json['gameType'] ?? 'tichu',
      maxPlayers: json['maxPlayers'] ?? 4,
      effectiveMaxPlayers: json['effectiveMaxPlayers'] is int
          ? json['effectiveMaxPlayers'] as int
          : (json['effectiveMaxPlayers'] is num
              ? (json['effectiveMaxPlayers'] as num).toInt()
              : null),
      skExpansions: expansions,
      randomSeating: json['randomSeating'] == true,
      allowMidGameJoin: json['allowMidGameJoin'] == true,
      // Absent from an older server's payload — treat as "no bot seats known"
      // so the break-in button stays hidden rather than failing on tap.
      botSeatCount: json['botSeatCount'] is int
          ? json['botSeatCount'] as int
          : (json['botSeatCount'] is num
              ? (json['botSeatCount'] as num).toInt()
              : 0),
    );
  }
}
