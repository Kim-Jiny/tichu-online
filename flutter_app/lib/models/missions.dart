// 미션·토큰·토큰 상점 상태(서버가 판정하고 앱은 보여 주기만 한다).

int _int(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

class MissionOffer {
  const MissionOffer({
    required this.key,
    required this.game,
    required this.tier,
    required this.tokens,
    required this.target,
    required this.picked,
  });

  final String key;
  final String game;

  /// 1 쉬움 · 2 보통 · 3 어려움
  final int tier;
  final int tokens;
  final int target;
  final bool picked;

  factory MissionOffer.fromJson(Map<String, dynamic> j) => MissionOffer(
    key: j['key'] as String? ?? '',
    game: j['game'] as String? ?? '',
    tier: _int(j['tier'], 1),
    tokens: _int(j['tokens']),
    target: _int(j['target'], 1),
    picked: j['picked'] == true,
  );
}

class ActiveMission {
  const ActiveMission({
    required this.key,
    required this.game,
    required this.tier,
    required this.tokens,
    required this.progress,
    required this.target,
    required this.done,
    required this.expiresDay,
  });

  final String key;
  final String game;
  final int tier;
  final int tokens;
  final int progress;
  final int target;
  final bool done;

  /// KST 날짜 'YYYY-MM-DD' — 이 날까지 유효.
  final String? expiresDay;

  factory ActiveMission.fromJson(Map<String, dynamic> j) => ActiveMission(
    key: j['key'] as String? ?? '',
    game: j['game'] as String? ?? '',
    tier: _int(j['tier'], 1),
    tokens: _int(j['tokens']),
    progress: _int(j['progress']),
    target: _int(j['target'], 1),
    done: j['status'] == 'done',
    expiresDay: j['expiresDay'] as String?,
  );
}

class GameOffers {
  const GameOffers({required this.rerollsLeft, required this.missions});
  final int rerollsLeft;
  final List<MissionOffer> missions;
}

class MissionsState {
  const MissionsState({
    required this.balance,
    required this.picksToday,
    required this.dailyPicks,
    required this.lifetimeDays,
    required this.minHumans,
    required this.streak,
    required this.streakDoneToday,
    required this.streakTarget,
    required this.streakBonus,
    required this.active,
    required this.offers,
    this.resetAtUtc,
  });

  final int balance;

  /// 오늘 이미 고른 미션 수(포기한 것도 센다)와 하루에 고를 수 있는 수.
  final int picksToday;
  final int dailyPicks;

  /// 고른 미션이 유효한 날 수, 그리고 미션으로 인정되는 최소 사람 수.
  final int lifetimeDays;
  final int minHumans;
  final int streak;
  final bool streakDoneToday;
  final int streakTarget;
  final int streakBonus;
  final DateTime? resetAtUtc;
  final List<ActiveMission> active;

  /// 게임 id('tichu' 등) → 오늘의 후보.
  final Map<String, GameOffers> offers;

  int get activeCount => active.where((m) => !m.done).length;

  /// 오늘 더 고를 수 있는지.
  bool get canPickMore => picksToday < dailyPicks;

  factory MissionsState.fromJson(Map<String, dynamic> j) {
    final offers = <String, GameOffers>{};
    final raw = j['offers'];
    if (raw is Map) {
      raw.forEach((game, v) {
        if (v is! Map) return;
        offers[game as String] = GameOffers(
          rerollsLeft: _int(v['rerollsLeft']),
          missions: [
            for (final m in (v['missions'] as List? ?? const []))
              MissionOffer.fromJson(Map<String, dynamic>.from(m as Map)),
          ],
        );
      });
    }
    return MissionsState(
      balance: _int(j['balance']),
      picksToday: _int(j['picksToday']),
      dailyPicks: _int(j['dailyPicks'], 3),
      lifetimeDays: _int(j['lifetimeDays'], 1),
      minHumans: _int(j['minHumans'], 2),
      streak: _int(j['streak']),
      streakDoneToday: j['streakDoneToday'] == true,
      streakTarget: _int(j['streakTarget'], 7),
      streakBonus: _int(j['streakBonus'], 5),
      resetAtUtc: j['resetAtUtc'] is String
          ? DateTime.tryParse(j['resetAtUtc'] as String)
          : null,
      active: [
        for (final m in (j['active'] as List? ?? const []))
          ActiveMission.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      offers: offers,
    );
  }
}

/// 미션을 깼을 때 서버가 밀어 주는 알림.
class MissionCompletion {
  const MissionCompletion({
    required this.key,
    required this.tokens,
    required this.streakBonus,
    required this.balance,
  });

  final String key;
  final int tokens;
  final int streakBonus;
  final int balance;

  factory MissionCompletion.fromJson(Map<String, dynamic> j) =>
      MissionCompletion(
        key: j['key'] as String? ?? '',
        tokens: _int(j['tokens']),
        streakBonus: _int(j['streakBonus']),
        balance: _int(j['balance']),
      );
}

class TokenProduct {
  const TokenProduct({
    required this.key,
    required this.kind,
    required this.variant,
    required this.price,
    required this.days,
    required this.ownedUntil,
    required this.equipped,
  });

  final String key;

  /// room_highlight · bubble_basic · bubble_premium
  final String kind;
  final int variant;
  final int price;
  final int days;
  final DateTime? ownedUntil;
  final bool equipped;

  bool get owned => ownedUntil != null && ownedUntil!.isAfter(DateTime.now());

  /// 장착하는 칸. 말풍선은 기본·상위가 한 칸을 같이 쓴다.
  String get slot => kind == 'room_highlight' ? 'room_highlight' : 'bubble';

  factory TokenProduct.fromJson(Map<String, dynamic> j) => TokenProduct(
    key: j['key'] as String? ?? '',
    kind: j['kind'] as String? ?? '',
    variant: _int(j['variant'], 1),
    price: _int(j['price']),
    days: _int(j['days'], 30),
    ownedUntil: j['ownedUntil'] is String
        ? DateTime.tryParse(j['ownedUntil'] as String)?.toLocal()
        : null,
    equipped: j['equipped'] == true,
  );
}

class TokenShopState {
  const TokenShopState({required this.balance, required this.products});
  final int balance;
  final List<TokenProduct> products;

  factory TokenShopState.fromJson(Map<String, dynamic> j) => TokenShopState(
    balance: _int(j['balance']),
    products: [
      for (final p in (j['products'] as List? ?? const []))
        TokenProduct.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
  );
}

/// 토큰 내역 한 줄(최신순으로 온다).
class TokenHistoryEntry {
  const TokenHistoryEntry({
    required this.id,
    required this.delta,
    required this.reason,
    required this.ref,
    required this.at,
  });

  final int id;
  final int delta;

  /// mission · streak · shop · admin_grant · admin_revoke
  final String reason;

  /// 미션 키 또는 상품 키(그 외에는 null).
  final String? ref;
  final DateTime? at;

  factory TokenHistoryEntry.fromJson(Map<String, dynamic> j) =>
      TokenHistoryEntry(
        id: _int(j['id']),
        delta: _int(j['delta']),
        reason: j['reason'] as String? ?? '',
        ref: j['ref'] as String?,
        at: j['createdAt'] is String
            ? DateTime.tryParse(j['createdAt'] as String)?.toLocal()
            : null,
      );
}
