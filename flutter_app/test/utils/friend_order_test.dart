import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/friend_order.dart';

/// The friends list order: waiting for a reply → online → last seen.
///
/// Sorting is one of those things that looks fine with three test accounts and
/// falls apart with forty real friends. The case that matters is the first
/// rule: someone messaged you and is waiting, and sorting by presence alone
/// buries them under everyone who happens to be online — in the one screen you
/// would go to looking for that message.

Map<String, dynamic> friend(
  String nickname, {
  bool online = false,
  String? lastSeen,
}) => {'nickname': nickname, 'isOnline': online, 'lastSeenAt': lastSeen};

List<String> order(
  List<Map<String, dynamic>> friends, [
  Map<String, int> unread = const {},
]) => sortFriends(friends, unread).map((f) => f['nickname'] as String).toList();

void main() {
  test('someone waiting for a reply comes first, even if offline', () {
    expect(
      order(
        [
          friend('온라인', online: true),
          friend('답장기다림', lastSeen: '2026-08-01 00:00:00'),
        ],
        {'답장기다림': 3},
      ),
      ['답장기다림', '온라인'],
    );
  });

  test('online beats offline when nobody is waiting', () {
    expect(
      order([
        friend('오프라인', lastSeen: '2026-08-14 00:00:00'),
        friend('온라인', online: true, lastSeen: '2026-01-01 00:00:00'),
      ]),
      ['온라인', '오프라인'],
    );
  });

  test('the offline tail is ordered by most recently seen', () {
    expect(
      order([
        friend('지난달', lastSeen: '2026-07-01 00:00:00'),
        friend('오늘', lastSeen: '2026-08-14 09:00:00'),
        friend('어제', lastSeen: '2026-08-13 09:00:00'),
      ]),
      ['오늘', '어제', '지난달'],
    );
  });

  test('all three rules together', () {
    expect(
      order(
        [
          friend('오래된온라인', online: true, lastSeen: '2020-01-01 00:00:00'),
          friend('방금본사람', lastSeen: '2026-08-14 11:59:00'),
          friend('메시지옴', lastSeen: '2019-01-01 00:00:00'),
          friend('작년에본사람', lastSeen: '2025-08-14 00:00:00'),
        ],
        {'메시지옴': 1},
      ),
      ['메시지옴', '오래된온라인', '방금본사람', '작년에본사람'],
    );
  });

  test('two people both waiting keep the presence rule between them', () {
    expect(
      order(
        [
          friend('기다림오프', lastSeen: '2026-08-14 00:00:00'),
          friend('기다림온라인', online: true),
        ],
        {'기다림오프': 2, '기다림온라인': 5},
      ),
      ['기다림온라인', '기다림오프'],
      reason: 'unread count size does not outrank being here now',
    );
  });

  test('a friend with no last-seen sinks instead of floating', () {
    // Old accounts predate the column; a null must not read as "just now".
    expect(
      order([friend('기록없음'), friend('작년', lastSeen: '2025-01-01 00:00:00')]),
      ['작년', '기록없음'],
    );
  });

  test('a tie is settled by name, so the list does not shuffle', () {
    final a = [friend('나'), friend('가'), friend('다')];
    expect(order(a), order(a));
    expect(order(a), ['가', '나', '다']);
  });

  test('the timestamp is read as UTC', () {
    // Naked server timestamps. Read as local they would still compare in the
    // right order — unless one of them has a marker and the other does not,
    // which is exactly the mix parseServerUtc exists to normalise.
    expect(
      order([
        friend('표식없음', lastSeen: '2026-08-14 03:00:00'),
        friend('Z붙음', lastSeen: '2026-08-14T04:00:00Z'),
      ]),
      ['Z붙음', '표식없음'],
    );
  });

  test('the input list is not reordered in place', () {
    // friendsData belongs to the service; sorting it there would reorder
    // whatever else is reading it mid-build.
    final input = [friend('나', online: true), friend('가')];
    sortFriends(input, const {});
    expect(input.first['nickname'], '나');
  });
}
