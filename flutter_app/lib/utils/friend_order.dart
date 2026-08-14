/// The order friends appear in.
///
/// Three rules, in this order:
///
///  1. someone who has written to you and is waiting for a reply;
///  2. someone who is online right now;
///  3. everyone else, most recently seen first.
///
/// The point of the first rule is that an unread message is the only entry in
/// this list that is *asking* for something. Sorting by presence alone buried
/// it under whoever happened to be online, and the list is exactly where you
/// would go looking for it.
///
/// Split out of the screen so the comparator can be tested: sorting bugs are
/// invisible until the list is long, and by then they read as "the app lost my
/// message".
library;

import 'server_time.dart';

/// Compare two friend rows. [unreadOf] gives the unread message count for a
/// nickname — 0 (or absent) when there is nothing waiting.
int compareFriends(
  Map<String, dynamic> a,
  Map<String, dynamic> b,
  int Function(String nickname) unreadOf,
) {
  final aNick = (a['nickname'] ?? '').toString();
  final bNick = (b['nickname'] ?? '').toString();

  final aWaiting = unreadOf(aNick) > 0;
  final bWaiting = unreadOf(bNick) > 0;
  if (aWaiting != bWaiting) return aWaiting ? -1 : 1;

  final aOnline = a['isOnline'] == true;
  final bOnline = b['isOnline'] == true;
  if (aOnline != bOnline) return aOnline ? -1 : 1;

  // Most recently seen first. Two people who are both online are both "now",
  // so this only really orders the offline tail — which is the half that
  // benefits from it.
  final aSeen = parseServerUtc(a['lastSeenAt']);
  final bSeen = parseServerUtc(b['lastSeenAt']);
  if (aSeen != null && bSeen != null && aSeen != bSeen) {
    return bSeen.compareTo(aSeen);
  }
  // A friend who has never been seen (an old account with no timestamp) sinks
  // rather than floating to the top on a null.
  if (aSeen == null && bSeen != null) return 1;
  if (aSeen != null && bSeen == null) return -1;

  // Same everything: settle it by name so the list does not shuffle between
  // rebuilds.
  return aNick.compareTo(bNick);
}

/// [friends] sorted by [compareFriends]. Returns a new list; the input is left
/// alone (it belongs to the service).
List<Map<String, dynamic>> sortFriends(
  List<Map<String, dynamic>> friends,
  Map<String, int> unreadByNickname,
) {
  final out = List<Map<String, dynamic>>.from(friends);
  out.sort((a, b) => compareFriends(a, b, (n) => unreadByNickname[n] ?? 0));
  return out;
}
