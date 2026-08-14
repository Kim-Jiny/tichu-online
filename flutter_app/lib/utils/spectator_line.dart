/// How many spectator names fit on the strip above the chat.
///
/// A popular room is what decides this. Twenty names in a Wrap would push the
/// chat off the screen, and a horizontal scroller would hide the names it did
/// not show with nothing to say so. The line is therefore cut to a character
/// budget and whatever is left becomes a tappable "외 N명" that opens the full
/// list.
///
/// Budget in characters, not in names: six short nicknames fit on one line and
/// six long ones do not.
library;

class SpectatorLine {
  /// Names to draw, in order.
  final List<String> shown;

  /// How many were left out. 0 when everyone fits.
  final int hidden;

  const SpectatorLine(this.shown, this.hidden);
}

SpectatorLine spectatorLine(List<String> names, {int budget = 34}) {
  final usable = names.where((n) => n.trim().isNotEmpty).toList();
  if (usable.isEmpty) return const SpectatorLine([], 0);
  final shown = <String>[];
  var used = 0;
  for (final name in usable) {
    // At least one name always shows, however long it is — "외 3명" alone
    // would say that someone is watching without saying who.
    if (shown.isNotEmpty && used + name.length > budget) break;
    shown.add(name);
    used += name.length + 2; // the ", " that follows it
  }
  return SpectatorLine(shown, usable.length - shown.length);
}
