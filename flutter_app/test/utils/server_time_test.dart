import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/server_time.dart';

/// Timestamps arrive from the server as naked UTC — `2026-08-14 03:22:57`,
/// with nothing in the string saying so. Every consumer that reads one with
/// plain DateTime.parse gets it right on a UTC machine and wrong by the
/// device's offset everywhere else, which is why this keeps coming back:
/// a mail deadline that has not passed reads as expired, a letter sent this
/// morning is dated tomorrow.
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
