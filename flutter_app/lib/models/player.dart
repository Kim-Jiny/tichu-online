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
    );
  }
}
