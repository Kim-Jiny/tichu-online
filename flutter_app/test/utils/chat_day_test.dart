import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/chat_day.dart';

/// Where the day dividers go in a DM thread.
///
/// Every bug here is invisible in a screenshot of a single day's chat, and
/// obvious to the person scrolling back through a month:
///  - a divider missing between 23:59 and 00:01, because eighteen minutes
///    apart looks like "same conversation" to duration arithmetic;
///  - a divider above every message, because the comparison used the exact
///    timestamp rather than the calendar day;
///  - the thread starting with no divider at all, so the oldest messages have
///    no date on them — which is the complaint that started this.

DateTime? at(String iso) => DateTime.parse(iso);

void main() {
  group('where a divider belongs', () {
    test('above the very first message, always', () {
      final msgs = [at('2026-08-13T10:00:00')];
      expect(needsDayDivider(msgs, 0, (m) => m), isTrue);
    });

    test('not between two messages on the same day', () {
      final msgs = [at('2026-08-13T10:00:00'), at('2026-08-13T22:30:00')];
      expect(needsDayDivider(msgs, 1, (m) => m), isFalse);
    });

    test('between two minutes that fall either side of midnight', () {
      final msgs = [at('2026-08-13T23:59:00'), at('2026-08-14T00:01:00')];
      expect(needsDayDivider(msgs, 1, (m) => m), isTrue,
          reason: 'two minutes apart, and still a different day');
    });

    test('across a month and a year boundary', () {
      expect(
        needsDayDivider(
          [at('2026-08-31T23:00:00'), at('2026-09-01T01:00:00')],
          1,
          (m) => m,
        ),
        isTrue,
      );
      expect(
        needsDayDivider(
          [at('2026-12-31T23:00:00'), at('2027-01-01T01:00:00')],
          1,
          (m) => m,
        ),
        isTrue,
      );
    });

    test('a message with no timestamp never introduces a day', () {
      // Labelling a divider for it would mean inventing the date on it.
      final msgs = [at('2026-08-13T10:00:00'), null];
      expect(needsDayDivider(msgs, 1, (m) => m), isFalse);
    });

    test('an undated message in the middle does not split a day in two', () {
      // The scan looks past it to the last message that actually has a time,
      // rather than treating the immediate neighbour as authoritative.
      final msgs = [
        at('2026-08-13T10:00:00'),
        null,
        at('2026-08-13T11:00:00'),
      ];
      expect(needsDayDivider(msgs, 2, (m) => m), isFalse);
    });

    test('but a real day change is still caught across one', () {
      final msgs = [
        at('2026-08-13T10:00:00'),
        null,
        at('2026-08-14T11:00:00'),
      ];
      expect(needsDayDivider(msgs, 2, (m) => m), isTrue);
    });

    test('an out-of-range index asks for nothing', () {
      expect(needsDayDivider(<DateTime?>[], 0, (m) => m), isFalse);
      expect(needsDayDivider([at('2026-08-13T10:00:00')], 5, (m) => m), isFalse);
    });
  });

  group('what the divider says', () {
    final now = DateTime(2026, 8, 13, 15, 30);

    test('today, at any hour of it', () {
      expect(chatDayLabel(DateTime(2026, 8, 13, 0, 1), now), ChatDayLabel.today);
      expect(
        chatDayLabel(DateTime(2026, 8, 13, 23, 59), now),
        ChatDayLabel.today,
      );
    });

    test('yesterday', () {
      expect(
        chatDayLabel(DateTime(2026, 8, 12, 9), now),
        ChatDayLabel.yesterday,
      );
    });

    test('yesterday across a month boundary', () {
      expect(
        chatDayLabel(DateTime(2026, 7, 31, 9), DateTime(2026, 8, 1, 10)),
        ChatDayLabel.yesterday,
      );
    });

    test('anything older gets a date', () {
      expect(chatDayLabel(DateTime(2026, 8, 11), now), ChatDayLabel.date);
      expect(chatDayLabel(DateTime(2025, 8, 13), now), ChatDayLabel.date,
          reason: 'same day and month, different year');
    });
  });
}
