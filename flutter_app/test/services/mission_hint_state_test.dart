import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/models/missions.dart';

MissionsState _state({required int picks, required DateTime resetAt}) =>
    MissionsState.fromJson({
      'balance': 0,
      'picksToday': picks,
      'dailyPicks': 3,
      'streak': 0,
      'streakDoneToday': false,
      'streakTarget': 7,
      'streakBonus': 5,
      'resetAtUtc': resetAt.toUtc().toIso8601String(),
      'active': [],
      'offers': {},
    });

void main() {
  final now = DateTime.utc(2026, 10, 16, 12);
  final tonight = now.add(const Duration(hours: 5));

  test('오늘 미션을 하나도 안 골랐을 때만 안내 대상', () {
    expect(_state(picks: 0, resetAt: tonight).unpickedToday(now), isTrue);
    expect(_state(picks: 1, resetAt: tonight).unpickedToday(now), isFalse);
    expect(_state(picks: 3, resetAt: tonight).unpickedToday(now), isFalse);
  });

  test('날이 바뀐(리셋 시각이 지난) 정보는 믿지 않는다', () {
    final stale = _state(
      picks: 0,
      resetAt: now.subtract(const Duration(minutes: 1)),
    );
    expect(stale.isCurrent(now), isFalse);
    expect(stale.unpickedToday(now), isFalse);
    expect(_state(picks: 0, resetAt: tonight).isCurrent(now), isTrue);
  });

  test('리셋 시각을 모르면 현재 것으로 본다', () {
    final st = MissionsState.fromJson({'picksToday': 0});
    expect(st.isCurrent(now), isTrue);
    expect(st.unpickedToday(now), isTrue);
  });
}
