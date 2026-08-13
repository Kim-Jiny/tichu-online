/// Grouping chat messages by the day they were sent.
///
/// Split from the widget because the rule is a date comparison, and date
/// comparisons are where this goes wrong in ways a screenshot will not show:
/// a message at 23:59 and one at 00:01 are eighteen hours apart by any
/// duration arithmetic and still belong to different days, and everything has
/// to happen in the reader's local time even though the wire carries UTC.
library;

/// Whether a divider belongs above the message at [index].
///
/// True for the first message, and whenever the local calendar day changes.
/// [dayOf] returns the message's local timestamp, or null when it has none —
/// a message with no usable time never introduces a day, since labelling a
/// divider would mean inventing the date on it.
bool needsDayDivider<T>(
  List<T> messages,
  int index,
  DateTime? Function(T) dayOf,
) {
  if (index < 0 || index >= messages.length) return false;
  final current = dayOf(messages[index]);
  if (current == null) return false;
  // Scan back past messages with no timestamp rather than treating the
  // immediate neighbour as authoritative: two undated messages in the middle
  // of a conversation would otherwise split one day into three.
  for (var i = index - 1; i >= 0; i--) {
    final prev = dayOf(messages[i]);
    if (prev == null) continue;
    return !isSameDay(prev, current);
  }
  // Nothing dated before it — this is where the conversation starts.
  return true;
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// How a day divider should read: today, yesterday, or a plain date.
enum ChatDayLabel { today, yesterday, date }

/// [now] is passed in rather than read, so "yesterday" can be tested without
/// waiting for midnight.
ChatDayLabel chatDayLabel(DateTime day, DateTime now) {
  if (isSameDay(day, now)) return ChatDayLabel.today;
  final yesterday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 1));
  if (isSameDay(day, yesterday)) return ChatDayLabel.yesterday;
  return ChatDayLabel.date;
}
