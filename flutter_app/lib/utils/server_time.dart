/// Reading timestamps the server sends.
///
/// The database columns are `timestamp without time zone` holding UTC, so what
/// arrives on the wire is a naked `2026-08-14 03:22:57` with nothing saying
/// which zone it is in. `DateTime.parse` reads that as LOCAL time, which is
/// silently correct on a UTC device and nine hours out in Seoul: a claim
/// deadline moves into the future, a "last seen" jumps forward, a sent date
/// shows tomorrow. Marking it as UTC before parsing is the whole fix.
///
/// Strings that already carry a marker (`…Z`, `…+09:00`) are left alone — some
/// payloads are serialized by node-pg with an offset attached, and adding a
/// second one would corrupt what was already right.
library;

DateTime? parseServerUtc(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toLocal();
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final marked = raw.endsWith('Z') || _hasOffset(raw) ? raw : '${raw}Z';
  return DateTime.tryParse(marked)?.toLocal();
}

/// A trailing `+09:00` / `-0500`, but not the `-` inside the date itself.
bool _hasOffset(String raw) {
  final timePart = raw.length > 11 ? raw.substring(11) : '';
  return timePart.contains('+') || timePart.contains('-');
}
