class BotStrategy {
  static const heuristic = 'heuristic';
  static const winrate = 'winrate';
  static const oracle = 'oracle';
  static const mixOracle = 'mixoracle';
  static const legacyMixExpectimax = 'mixexpectimax';
  static const pimcPlay = 'pimc_play';
  static const pimcFull = 'pimc_full';
  static const expectimax = 'expectimax';
  static const expectimaxSmart = 'expectimax_smart';
  static const all = [
    heuristic,
    winrate,
    oracle,
    mixOracle,
    pimcPlay,
    pimcFull,
    expectimax,
    expectimaxSmart,
    legacyMixExpectimax,
  ];
}

class Player {
  final String id;
  final String name;
  final String position; // 'self', 'partner', 'left', 'right'
  final int cardCount;
  final bool hasSmallTichu;
  final bool hasLargeTichu;
  final bool hasExchanged;
  final bool hasFinished;
  final int finishPosition;
  final bool isHost;
  final bool connected;
  final bool isReady;
  final int timeoutCount;
  final String? titleKey;
  final String? titleName;
  final String? bannerKey;
  /// Public avatar URL (paid profile-photo item, active + unexpired). Null =
  /// default avatar. Always null for bots. Server resolves eligibility.
  final String? photoUrl;

  /// Server-side flag; the engines never knew, so this is spliced in when the
  /// state is sent. Lets a seat draw a bot avatar instead of an empty circle.
  final bool isBot;
  final String? botSpeed;
  final String? botStrategy;
  /// Player's account level. Null for bots and (transitionally) for old
  /// server responses that haven't redeployed level support yet.
  final int? level;
  /// Current season rating for the game type this room hosts. Null for bots
  /// and for older server responses. Used by ranked waiting rooms.
  final int? seasonRating;

  Player({
    required this.id,
    required this.name,
    this.position = '',
    this.cardCount = 0,
    this.hasSmallTichu = false,
    this.hasLargeTichu = false,
    this.hasExchanged = false,
    this.hasFinished = false,
    this.finishPosition = 0,
    this.isHost = false,
    this.connected = true,
    this.isReady = false,
    this.timeoutCount = 0,
    this.titleKey,
    this.titleName,
    this.bannerKey,
    this.photoUrl,
    this.isBot = false,
    this.botSpeed,
    this.botStrategy,
    this.level,
    this.seasonRating,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      position: json['position'] ?? '',
      cardCount: json['cardCount'] ?? 0,
      hasSmallTichu: json['hasSmallTichu'] ?? false,
      hasLargeTichu: json['hasLargeTichu'] ?? false,
      hasExchanged: json['hasExchanged'] ?? false,
      hasFinished: json['hasFinished'] ?? false,
      finishPosition: json['finishPosition'] ?? 0,
      isHost: json['isHost'] ?? false,
      connected: json['connected'] ?? true,
      isReady: json['isReady'] ?? false,
      timeoutCount: json['timeoutCount'] ?? 0,
      titleKey: json['titleKey'] as String?,
      titleName: json['titleName'] as String?,
      bannerKey: json['bannerKey'] as String?,
      photoUrl: json['photoUrl'] as String?,
      isBot: json['isBot'] == true,
      botSpeed: json['botSpeed'] as String?,
      botStrategy: json['botStrategy'] as String?,
      level: (json['level'] as num?)?.toInt(),
      seasonRating: (json['seasonRating'] as num?)?.toInt(),
    );
  }
}
