/// Reading timestamps the server sends.
///
/// A guard, not a fix for anything currently broken. Today every timestamp
/// leaves the server marked: the columns are `timestamp without time zone`
/// holding UTC, the pool pins its session to UTC, and node-pg therefore builds
/// a Date that JSON.stringify writes as `2026-08-14T03:22:57.000Z` — verified
/// identical under TZ=UTC, Asia/Seoul and America/New_York, since the session
/// zone decides it rather than the host's.
///
/// What this protects against is a payload that arrives NAKED —
/// `2026-08-14 03:22:57` with nothing saying which zone it is in — which is
/// what any hand-built timestamp string would be. `DateTime.parse` reads that
/// as LOCAL, silently correct on a UTC device and nine hours out in Seoul: a
/// claim deadline moves into the future, a sent date shows tomorrow.
///
/// Strings that already carry a marker (`…Z`, `…+09:00`) are passed through
/// untouched — adding a second one would corrupt what was already right.
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
