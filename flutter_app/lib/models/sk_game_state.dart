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
  final String? photoUrl;

  /// Server-side flag; the engines never knew, so this is spliced in when the
  /// state is sent. Lets a seat draw a bot avatar instead of an empty circle.
  final bool isBot;

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
    this.photoUrl,
    this.isBot = false,
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
      photoUrl: json['photoUrl'] as String?,
      isBot: json['isBot'] == true,
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
  final bool lastTrickVoided;
  final String? trickStarter;
  final String? roundStarter;
  final int? turnDeadline;

  /// Enabled Skull King expansions for this game.
  /// Subset of `['kraken', 'white_whale', 'loot', 'pirate_abilities']`.
  final List<String> expansions;

  /// 해적 능력을 쓰는 중이면 { playerId, pirate, cardId } (phase == 'pirate_ability').
  final SKPendingAbility? pendingAbility;

  /// 내가 능력 주인일 때만 오는 비공개 정보: Bendt 가 뽑은 카드(drawn), Juanita 가 보는 안 나눈 카드(undealt).
  final List<String> abilityDrawn;
  final List<String> abilityUndealt;

  /// 방금 쓴 능력(모두에게 보여 줄 공개 정보)과 그 일련번호 — 번호가 바뀔 때 한 번만 알린다.
  final SKAbilityEvent? lastAbility;
  final int abilitySeq;

  /// 이번 라운드 Rascal 내기 { playerId: 0|10|20 }.
  final Map<String, int> rascalWagers;

  bool get hasPirateAbilities => expansions.contains('pirate_abilities');

  /// 지금 내가 해적 능력을 쓸 차례인가.
  bool get isMyAbilityTurn {
    final ab = pendingAbility;
    if (ab == null || phase != 'pirate_ability') return false;
    return players.any((p) => p.position == 'self' && p.id == ab.playerId);
  }

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
    this.lastTrickVoided = false,
    this.trickStarter,
    this.roundStarter,
    this.turnDeadline,
    this.expansions = const [],
    this.pendingAbility,
    this.abilityDrawn = const [],
    this.abilityUndealt = const [],
    this.lastAbility,
    this.abilitySeq = 0,
    this.rascalWagers = const {},
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

    List<String> expansions = const [];
    if (json['expansions'] is List) {
      expansions = (json['expansions'] as List).whereType<String>().toList(
        growable: false,
      );
    }

    final info = json['abilityInfo'];
    final Map<String, int> wagers = {};
    if (json['rascalWagers'] is Map) {
      (json['rascalWagers'] as Map).forEach((k, v) {
        wagers[k.toString()] = (v as num?)?.toInt() ?? 0;
      });
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
      lastTrickVoided: json['lastTrickVoided'] == true,
      trickStarter: json['trickStarter'],
      roundStarter: json['roundStarter'],
      turnDeadline: json['turnDeadline'] as int?,
      expansions: expansions,
      pendingAbility: json['pendingAbility'] is Map
          ? SKPendingAbility.fromJson(
              Map<String, dynamic>.from(json['pendingAbility'] as Map),
            )
          : null,
      abilityDrawn: info is Map && info['drawn'] is List
          ? List<String>.from(info['drawn'] as List)
          : const [],
      abilityUndealt: info is Map && info['undealt'] is List
          ? List<String>.from(info['undealt'] as List)
          : const [],
      lastAbility: json['lastAbility'] is Map
          ? SKAbilityEvent.fromJson(
              Map<String, dynamic>.from(json['lastAbility'] as Map),
            )
          : null,
      abilitySeq: (json['abilitySeq'] as num?)?.toInt() ?? 0,
      rascalWagers: wagers,
    );
  }
}

/// 이긴 해적의 능력을 쓰는 중인 사람과 능력 이름(rascal/rosie/bendt/juanita/harry).
class SKPendingAbility {
  final String playerId;
  final String pirate;
  final String? cardId;

  const SKPendingAbility({
    required this.playerId,
    required this.pirate,
    this.cardId,
  });

  factory SKPendingAbility.fromJson(Map<String, dynamic> json) =>
      SKPendingAbility(
        playerId: json['playerId']?.toString() ?? '',
        pirate: json['pirate']?.toString() ?? '',
        cardId: json['cardId']?.toString(),
      );
}

/// 방금 쓴 능력의 공개 결과 — Rosie 는 지목한 사람, Bendt 는 바꾼 장수, Rascal 은 내기 점수,
/// Harry 는 입찰 변화(delta)와 새 입찰, Juanita 는 "봤다"는 사실만.
class SKAbilityEvent {
  final String playerId;
  final String pirate;
  final String? targetId;
  final int? count;
  final int? wager;
  final int? delta;
  final int? bid;

  const SKAbilityEvent({
    required this.playerId,
    required this.pirate,
    this.targetId,
    this.count,
    this.wager,
    this.delta,
    this.bid,
  });

  factory SKAbilityEvent.fromJson(Map<String, dynamic> json) => SKAbilityEvent(
    playerId: json['playerId']?.toString() ?? '',
    pirate: json['pirate']?.toString() ?? '',
    targetId: json['targetId']?.toString(),
    count: (json['count'] as num?)?.toInt(),
    wager: (json['wager'] as num?)?.toInt(),
    delta: (json['delta'] as num?)?.toInt(),
    bid: (json['bid'] as num?)?.toInt(),
  );
}
