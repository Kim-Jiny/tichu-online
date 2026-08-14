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
