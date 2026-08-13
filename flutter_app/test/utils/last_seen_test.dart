import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/last_seen.dart';

/// Bucketing "when was this friend last here".
///
/// All the interesting cases are boundaries, and none of them are visible by
/// looking at the screen: 60 minutes has to become "1시간" rather than "60분",
/// and a timestamp from the future — routine, because a phone clock and a
/// server clock are two different clocks — must not render as a negative
/// count.

void main() {
  final now = DateTime.utc(2026, 8, 13, 12, 0);
  LastSeen ago(Duration d) => lastSeenBucket(now.subtract(d), now);

  test('under a minute has no number to show', () {
    expect(ago(const Duration(seconds: 5)).unit, LastSeenUnit.justNow);
    expect(ago(const Duration(seconds: 59)).unit, LastSeenUnit.justNow);
  });

  test('minutes, up to the hour', () {
    expect(ago(const Duration(minutes: 1)), const LastSeen(LastSeenUnit.minutes, 1));
    expect(ago(const Duration(minutes: 59)), const LastSeen(LastSeenUnit.minutes, 59));
  });

  test('exactly an hour rolls over, rather than reading "60분 전"', () {
    expect(ago(const Duration(minutes: 60)), const LastSeen(LastSeenUnit.hours, 1));
  });

  test('hours, up to the day', () {
    expect(ago(const Duration(hours: 23)), const LastSeen(LastSeenUnit.hours, 23));
    expect(ago(const Duration(hours: 24)), const LastSeen(LastSeenUnit.days, 1));
  });

  test('days, until a count stops being informative', () {
    expect(ago(const Duration(days: 30)), const LastSeen(LastSeenUnit.days, 30));
    // "182일 전" says less than "over a month".
    expect(ago(const Duration(days: 31)).unit, LastSeenUnit.longAgo);
  });

  test('a future timestamp reads as just now, not as a negative', () {
    // Two clocks: the phone's and the server's. They disagree by seconds all
    // the time and by hours when a device timezone is wrong.
    final ahead = lastSeenBucket(now.add(const Duration(hours: 3)), now);
    expect(ahead.unit, LastSeenUnit.justNow);
    expect(ahead.amount, 0);
  });
}
