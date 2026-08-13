/// How long ago a friend was last connected, bucketed for display.
///
/// Split from the widget so the arithmetic can be tested — the edges are where
/// this goes wrong ("60분 전" instead of "1시간 전", or a negative number when
/// a device clock runs ahead of the server) and none of that is visible in a
/// screenshot.
enum LastSeenUnit {
  /// Under a minute. Shown as "방금", with no number.
  justNow,
  minutes,
  hours,
  days,

  /// Long enough that a count stops meaning anything — "182일 전" tells you
  /// less than a date does.
  longAgo,
}

class LastSeen {
  final LastSeenUnit unit;

  /// How many [unit]s, or 0 for [LastSeenUnit.justNow] and
  /// [LastSeenUnit.longAgo].
  final int amount;

  const LastSeen(this.unit, this.amount);

  @override
  bool operator ==(Object other) =>
      other is LastSeen && other.unit == unit && other.amount == amount;

  @override
  int get hashCode => Object.hash(unit, amount);

  @override
  String toString() => 'LastSeen($unit, $amount)';
}

/// Bucket [lastSeen] relative to [now].
///
/// A future timestamp reads as [LastSeenUnit.justNow] rather than as a
/// negative count. The two clocks involved are a phone's and a server's, and
/// they disagree by seconds routinely and by hours when a device timezone is
/// misconfigured — "-3시간 전 접속" would be the visible result.
LastSeen lastSeenBucket(DateTime lastSeen, DateTime now) {
  final d = now.difference(lastSeen);
  if (d.inMinutes < 1) return const LastSeen(LastSeenUnit.justNow, 0);
  if (d.inMinutes < 60) return LastSeen(LastSeenUnit.minutes, d.inMinutes);
  if (d.inHours < 24) return LastSeen(LastSeenUnit.hours, d.inHours);
  if (d.inDays <= 30) return LastSeen(LastSeenUnit.days, d.inDays);
  return const LastSeen(LastSeenUnit.longAgo, 0);
}
