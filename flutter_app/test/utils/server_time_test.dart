import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/server_time.dart';

/// Server timestamps arrive marked today (`…Z`) because the pool pins its
/// session to UTC and node-pg serializes accordingly. This covers the case
/// that marking protects against: a NAKED `2026-08-14 03:22:57`, which
/// DateTime.parse reads as local — right on a UTC machine, wrong by the
/// device's offset everywhere else. A mail deadline that has not passed then
/// reads as expired, and a letter sent this morning is dated tomorrow.
///
/// The tests compare instants, not wall-clock text, so they hold whatever
/// timezone the machine running them is in.

void main() {
  test('a naked timestamp is read as UTC, not as local time', () {
    final parsed = parseServerUtc('2026-08-14 03:22:57');
    expect(parsed, isNotNull);
    expect(
      parsed!.toUtc(),
      DateTime.utc(2026, 8, 14, 3, 22, 57),
      reason: 'read as local, this drifts by the device offset',
    );
  });

  test('the T separator is handled the same way', () {
    expect(
      parseServerUtc('2026-08-14T03:22:57')!.toUtc(),
      DateTime.utc(2026, 8, 14, 3, 22, 57),
    );
  });

  test('a string that already says Z is left alone', () {
    expect(
      parseServerUtc('2026-08-14T03:22:57Z')!.toUtc(),
      DateTime.utc(2026, 8, 14, 3, 22, 57),
    );
  });

  test('an explicit offset is respected, not overwritten', () {
    // node-pg serializes some payloads with the offset attached. Appending Z
    // to one of those would move it by the offset a second time.
    expect(
      parseServerUtc('2026-08-14T12:22:57+09:00')!.toUtc(),
      DateTime.utc(2026, 8, 14, 3, 22, 57),
    );
    expect(
      parseServerUtc('2026-08-13T22:22:57-05:00')!.toUtc(),
      DateTime.utc(2026, 8, 14, 3, 22, 57),
    );
  });

  test('the date\'s own hyphens are not mistaken for an offset', () {
    // '2026-08-14 03:22:57' is full of hyphens; only a trailing one counts.
    expect(parseServerUtc('2026-08-14 03:22:57')!.toUtc().hour, 3);
  });

  test('microseconds survive', () {
    expect(
      parseServerUtc('2026-08-14 03:22:57.123')!.toUtc(),
      DateTime.utc(2026, 8, 14, 3, 22, 57, 123),
    );
  });

  test('the result is in local time, ready to display', () {
    final parsed = parseServerUtc('2026-08-14 03:22:57')!;
    expect(parsed.isUtc, isFalse);
  });

  test('nothing in, nothing out — no exception', () {
    expect(parseServerUtc(null), isNull);
    expect(parseServerUtc(''), isNull);
    expect(parseServerUtc('   '), isNull);
    expect(parseServerUtc('not a date'), isNull);
  });

  test('a DateTime passes through', () {
    final dt = DateTime.utc(2026, 8, 14, 3);
    expect(parseServerUtc(dt)!.toUtc(), dt);
  });
}
