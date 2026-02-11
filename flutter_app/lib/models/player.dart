class Player {
  final String id;
  final String name;
  final String position; // 'self', 'partner', 'left', 'right'
  final int cardCount;
  final bool hasSmallTichu;
  final bool hasLargeTichu;
  final bool hasFinished;
  final int finishPosition;
  final bool isHost;
  final bool connected;
  final bool isReady;
  final int timeoutCount;
  final String? titleKey;
  final String? titleName;

  Player({
    required this.id,
    required this.name,
    this.position = '',
    this.cardCount = 0,
    this.hasSmallTichu = false,
    this.hasLargeTichu = false,
    this.hasFinished = false,
    this.finishPosition = 0,
    this.isHost = false,
    this.connected = true,
    this.isReady = false,
    this.timeoutCount = 0,
    this.titleKey,
    this.titleName,
  });

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      position: json['position'] ?? '',
      cardCount: json['cardCount'] ?? 0,
      hasSmallTichu: json['hasSmallTichu'] ?? false,
      hasLargeTichu: json['hasLargeTichu'] ?? false,
      hasFinished: json['hasFinished'] ?? false,
      finishPosition: json['finishPosition'] ?? 0,
      isHost: json['isHost'] ?? false,
      connected: json['connected'] ?? true,
      isReady: json['isReady'] ?? false,
      timeoutCount: json['timeoutCount'] ?? 0,
      titleKey: json['titleKey'] as String?,
      titleName: json['titleName'] as String?,
    );
  }
}
