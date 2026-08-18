/// Whether a letter still wants something from the player.
///
/// Not "unread". A letter with gold in it is not finished when it has been
/// opened — it is finished when the gold has been taken out. A badge that
/// clears on open lets someone read the letter, mean to claim later, and never
/// be reminded again, which is exactly how a reward goes unclaimed.
///
/// A reward whose deadline has passed stops counting: nothing is left to
/// collect, and a badge for it would only nag about something already lost.
///
/// Shared so the list highlight, the mailbox badge and the lobby badge cannot
/// drift apart — three places asking the same question have to get the same
/// answer.
library;

import 'server_time.dart';

bool mailNeedsAttention(Map<String, dynamic> mail, {DateTime? now}) {
  if (mail['read_at'] == null) return true;
  final gold = (mail['reward_gold'] as num?)?.toInt() ?? 0;
  final itemKey = (mail['reward_item_key'] ?? '').toString();
  final hasReward = gold > 0 || itemKey.isNotEmpty;
  if (!hasReward || mail['claimed_at'] != null) return false;
  final expiresAt = parseServerUtc(mail['expires_at']);
  if (expiresAt == null) return true;
  return expiresAt.isAfter(now ?? DateTime.now());
}

/// 우편함 배지에 찍을 수.
///
/// 목록은 서버가 최근 [50]통까지만 내려준다. 그 목록만 세면 우편이 쌓인
/// 사람에게는 실제보다 적은 수가 찍힌다 — 배지가 "3" 인데 열어보니 밀린 게
/// 그보다 많은 상황. 서버는 정확한 수를 같이 내려주므로, 목록에서 센 수와의
/// 차이를 "페이지 밖에 남은 것" 으로 들고 있다가 더한다.
///
/// 서버 수를 그대로 쓰지 않는 이유는, 읽거나 수령하면 목록은 그 자리에서
/// 바뀌는데 서버가 세어준 수는 다음 갱신까지 그대로이기 때문이다. 눈앞의
/// 변화는 목록에서 세고, 페이지 밖은 서버 수에서 가져온다.
int mailUnreadBeyondPage(int countedInPage, int? serverUnread) {
  if (serverUnread == null) return 0;
  final beyond = serverUnread - countedInPage;
  return beyond > 0 ? beyond : 0;
}
