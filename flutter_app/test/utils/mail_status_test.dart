import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/mail_status.dart';

/// When does a letter stop asking for attention?
///
/// Reading it is not enough when there is gold inside. The badge used to clear
/// on open, which meant: read it, mean to claim later, never get reminded —
/// and the reward quietly expires. So the mark comes off when the reward does,
/// not when the letter is opened.
///
/// The client counts this for the badge and the server counts it for the
/// payload; they have to agree, or the number on the lobby icon disagrees with
/// the list behind it.

Map<String, dynamic> letter({
  Object? readAt = '2026-08-14 00:00:00',
  Object? claimedAt,
  int gold = 0,
  String? item,
  Object? expiresAt,
}) => {
  'read_at': readAt,
  'claimed_at': claimedAt,
  'reward_gold': gold,
  'reward_item_key': item,
  'expires_at': expiresAt,
};

void main() {
  final now = DateTime.utc(2026, 8, 14, 12);

  test('unread always counts, reward or not', () {
    expect(mailNeedsAttention(letter(readAt: null), now: now), isTrue);
    expect(mailNeedsAttention(letter(readAt: null, gold: 500), now: now), isTrue);
  });

  test('read with nothing in it is done', () {
    expect(mailNeedsAttention(letter(), now: now), isFalse);
  });

  test('read but the gold is still in it — still counts', () {
    expect(
      mailNeedsAttention(letter(gold: 500), now: now),
      isTrue,
      reason: 'this is the case that made rewards go unclaimed',
    );
  });

  test('an item reward behaves the same as gold', () {
    expect(mailNeedsAttention(letter(item: 'banner_pio_dawn'), now: now), isTrue);
  });

  test('claimed is done', () {
    expect(
      mailNeedsAttention(
        letter(gold: 500, claimedAt: '2026-08-14 01:00:00'),
        now: now,
      ),
      isFalse,
    );
  });

  test('a deadline still ahead keeps it counting', () {
    expect(
      mailNeedsAttention(letter(gold: 500, expiresAt: '2026-08-20 00:00:00'), now: now),
      isTrue,
    );
  });

  test('a deadline that has passed stops it — nothing left to collect', () {
    // Nagging about a reward that can no longer be taken is just noise.
    expect(
      mailNeedsAttention(letter(gold: 500, expiresAt: '2026-08-10 00:00:00'), now: now),
      isFalse,
    );
  });

  test('the deadline is read as UTC, not as the device\'s local time', () {
    // 03:00 UTC on the 14th. A device nine hours ahead reading it as local
    // would place it in the past and drop the badge early.
    expect(
      mailNeedsAttention(
        letter(gold: 500, expiresAt: '2026-08-14 15:00:00'),
        now: DateTime.utc(2026, 8, 14, 12),
      ),
      isTrue,
    );
  });

  test('a zero-gold, no-item letter is not a reward letter', () {
    expect(mailNeedsAttention(letter(gold: 0, item: ''), now: now), isFalse);
  });

  group('배지 수 — 목록은 50통까지만 내려온다', () {
    test('페이지에 다 들어오면 더할 게 없다', () {
      expect(mailUnreadBeyondPage(3, 3), 0);
    });

    test('목록에 안 실린 만큼을 더한다', () {
      // 서버는 62통이 밀렸다고 하는데 목록에는 50통만 왔고 그중 47통이
      // 대기 중이면, 배지는 47 이 아니라 62 가 되어야 한다.
      expect(mailUnreadBeyondPage(47, 62), 15);
    });

    test('읽어서 목록 쪽이 줄어도 음수로 가지 않는다', () {
      // 서버 수는 다음 갱신까지 그대로다. 그 사이 몇 통을 읽으면 목록에서
      // 센 수가 서버 수보다 커질 수 있다.
      expect(mailUnreadBeyondPage(9, 5), 0);
    });

    test('서버가 수를 안 보내면 목록만 믿는다', () {
      expect(mailUnreadBeyondPage(4, null), 0);
    });
  });
}
