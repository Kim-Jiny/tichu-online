import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/notice_badge.dart';

/// 공지 NEW 배지는 "안 읽음" 만으로 달지 않는다.
///
/// 안 읽었다는 사실만 보면 공지가 쌓일수록 불리해진다 — 오래 안 들어온 사람은
/// 그동안 올라온 게 전부 NEW 로 남고, 계정을 새로 만들거나 기기를 옮겨도
/// 마찬가지다. 배지는 "볼 게 생겼다" 는 신호여야지 밀린 숙제 목록이 아니다.

final now = DateTime(2026, 8, 20, 12, 0);

/// 서버가 주는 모양: 표식 없는 UTC 문자열.
Map<String, dynamic> notice(int id, Duration ago) => {
  'id': id,
  'title': '공지 $id',
  'published_at': now.toUtc().subtract(ago).toIso8601String().split('.').first,
};

void main() {
  test('사흘 안에 올라온 안 읽은 공지는 NEW', () {
    expect(isNoticeNewFor(notice(1, const Duration(hours: 2)), {}, now: now),
        isTrue);
    expect(
      isNoticeNewFor(notice(2, const Duration(days: 2, hours: 23)), {}, now: now),
      isTrue,
    );
  });

  test('사흘이 지나면 안 읽었어도 NEW 가 아니다', () {
    expect(
      isNoticeNewFor(notice(3, const Duration(days: 3, hours: 1)), {}, now: now),
      isFalse,
    );
    expect(isNoticeNewFor(notice(4, const Duration(days: 30)), {}, now: now),
        isFalse);
  });

  test('읽었으면 최근 것이어도 NEW 가 아니다', () {
    expect(
      isNoticeNewFor(notice(5, const Duration(hours: 1)), {5}, now: now),
      isFalse,
    );
  });

  test('배지 숫자는 최근 것만 센다', () {
    final list = [
      notice(10, const Duration(hours: 1)),
      notice(11, const Duration(days: 1)),
      notice(12, const Duration(days: 10)),
      notice(13, const Duration(days: 400)),
    ];
    expect(countNewNotices(list, {}, now: now), 2);
    expect(countNewNotices(list, {10}, now: now), 1, reason: '읽은 건 빠진다');
  });

  test('날짜를 못 읽으면 안 읽음으로 둔다', () {
    // 배지를 잘못 놓치는 것보다 남기는 쪽이 덜 나쁘다.
    expect(isNoticeNewFor({'id': 20, 'published_at': null}, {}, now: now), isTrue);
    expect(isNoticeNewFor({'id': 21, 'published_at': '이상한값'}, {}, now: now),
        isTrue);
  });

  test('서버 시각을 UTC 로 읽는다', () {
    // 표식 없는 서버 시각을 로컬(KST)로 읽으면 아홉 시간이 밀린다. 그러면
    // 사흘 하고 두 시간 지난 공지가 아직 사흘 안쪽으로 보여 NEW 가 남는다.
    final justOver = now
        .toUtc()
        .subtract(const Duration(days: 3, hours: 2))
        .toIso8601String()
        .split('.')
        .first;
    expect(
      isNoticeNewFor({'id': 30, 'published_at': justOver}, {}, now: now),
      isFalse,
    );
  });

  test('created_at 만 있어도 읽는다', () {
    final v = now.toUtc().subtract(const Duration(hours: 3)).toIso8601String();
    expect(isNoticeNewFor({'id': 40, 'created_at': v}, {}, now: now), isTrue);
  });
}
