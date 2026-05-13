/// Client-side mirror of the server's `tc_compute_level` SQL function
/// (see `server/db/database.js`). Both sides MUST stay in sync — when the
/// curve changes, update both files in the same commit.
///
/// Curve (cost to go from level L to L+1):
///   Lv 1–9   : 100 + (L-1)*5     → 100, 105, ..., 140
///   Lv 10–19 : 150 + (L-10)*10   → 150, 160, ..., 240
///   Lv 20–29 : 260 + (L-20)*20   → 260, 280, ..., 440
///   Lv 30–39 : 480 + (L-30)*40   → 480, 520, ..., 840
///   Lv 40+   : 920 + (L-40)*80
class LevelCurve {
  const LevelCurve._();

  /// EXP cost to advance from [level] to [level]+1.
  static int costForLevel(int level) {
    if (level <= 0) return 100;
    if (level <= 9) return 100 + (level - 1) * 5;
    if (level <= 19) return 150 + (level - 10) * 10;
    if (level <= 29) return 260 + (level - 20) * 20;
    if (level <= 39) return 480 + (level - 30) * 40;
    return 920 + (level - 40) * 80;
  }

  /// Cumulative EXP needed to first reach [level]. T(1) = 0.
  static int thresholdForLevel(int level) {
    if (level <= 1) return 0;
    var total = 0;
    for (var l = 1; l < level; l++) {
      total += costForLevel(l);
    }
    return total;
  }

  /// Progress within the current level. Returns the EXP earned past the
  /// level's threshold and the cost to clear it. Used by the profile
  /// header's thin progress bar.
  static LevelProgress progress(int level, int expTotal) {
    final lv = level <= 0 ? 1 : level;
    final cost = costForLevel(lv);
    final threshold = thresholdForLevel(lv);
    var exp = expTotal - threshold;
    if (exp < 0) exp = 0;
    if (exp > cost) exp = cost;
    return LevelProgress(exp, cost);
  }
}

class LevelProgress {
  final int expInLevel;
  final int expToNext;
  const LevelProgress(this.expInLevel, this.expToNext);

  double get fraction => expToNext == 0 ? 1.0 : expInLevel / expToNext;
}
