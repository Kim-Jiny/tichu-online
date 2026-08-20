import 'server_time.dart';

/// 공지 NEW 배지 판정.
///
/// 안 읽었다는 사실만으로 배지를 달면 공지가 쌓일수록 불리해진다. 오래 안
/// 들어온 사람은 그동안 올라온 것이 전부 NEW 로 남고, 계정을 새로 만들거나
/// 기기를 옮겨도 마찬가지다(설치 시점 부트스트랩이 있지만 그건 기기 단위다).
/// 배지는 "볼 게 생겼다" 는 신호여야지 밀린 숙제 목록이 아니다.
///
/// 그래서 올라온 지 사흘이 지난 공지는 안 읽었어도 배지를 달지 않는다.
/// 목록에는 그대로 남고, 열면 읽음 처리되는 것도 예전과 같다.
///
/// GameService 가 아니라 여기 있는 이유는 테스트다 — GameService 는 네트워크와
/// FCM 에 묶여 있어 테스트에서 세우기 어렵고, 그러면 규칙을 테스트에 다시
/// 적게 된다. 그런 테스트는 코드가 어긋나도 초록으로 남는다.
const Duration noticeNewWindow = Duration(days: 3);

/// 이 공지에 NEW 를 달아야 하는가.
///
/// [now] 는 테스트용. 안 넘기면 현재 시각.
bool isNoticeNewFor(
  Map<String, dynamic> notice,
  Set<int> readIds, {
  DateTime? now,
}) {
  final id = notice['id'];
  if (id is! int || readIds.contains(id)) return false;

  // 서버 시각은 UTC 로 저장된다 — 표식 없는 값을 로컬로 읽으면 KST 기준
  // 아홉 시간이 밀려서, 사흘 지난 공지가 아직 이틀 반으로 보인다.
  final published = parseServerUtc(
    notice['published_at'] ?? notice['created_at'],
  );

  // 날짜를 못 읽으면 예전처럼 안 읽음으로 둔다. 배지를 잘못 놓치는 것보다
  // 남기는 쪽이 덜 나쁘다.
  if (published == null) return true;

  return (now ?? DateTime.now()).difference(published) <= noticeNewWindow;
}

/// 배지에 찍을 숫자.
int countNewNotices(
  List<Map<String, dynamic>> notices,
  Set<int> readIds, {
  DateTime? now,
}) {
  var count = 0;
  for (final n in notices) {
    if (isNoticeNewFor(n, readIds, now: now)) count++;
  }
  return count;
}
