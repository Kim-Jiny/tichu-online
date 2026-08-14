import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import '../utils/gold_format.dart';
import '../utils/server_time.dart';

/// 운영자 우편함 — letters the staff sent to this player.
///
/// A letter is not a notice and not an inquiry reply, and the difference is
/// visible here: it is addressed to one person, it is read or unread for that
/// person alone, and it can be holding gold or an item that has to be taken
/// out. That last part is why the reward sits in its own row with its own
/// button instead of being written into the body — a payout the player has to
/// find inside a paragraph is a payout that goes unclaimed.
class MailboxScreen extends StatefulWidget {
  const MailboxScreen({super.key});

  @override
  State<MailboxScreen> createState() => _MailboxScreenState();
}

class _MailboxScreenState extends State<MailboxScreen> {
  int? _claiming;

  @override
  void initState() {
    super.initState();
    // Deferred: loadMailbox notifies, and initState runs inside the build
    // phase (the notices screen learned this the hard way).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<GameService>().loadMailbox();
    });
  }

  void _claim(GameService game, int id) {
    setState(() => _claiming = id);
    game.claimMail(id);
  }

  /// A claim's outcome arrives as a message, not a reply, so the result is
  /// picked up on the next rebuild rather than awaited.
  void _drainReward(GameService game) {
    final reward = game.takeMailReward();
    if (reward == null) return;
    _claiming = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).mailboxClaimedToast),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  String _rewardLabel(L10n l10n, Map<String, dynamic> mail) {
    final gold = (mail['reward_gold'] as num?)?.toInt() ?? 0;
    if (gold > 0) return l10n.mailboxRewardGold(formatGold(gold));
    final itemName = (mail['item_name_ko'] ?? mail['reward_item_key'] ?? '')
        .toString();
    if (itemName.isEmpty) return '';
    final days = (mail['reward_days'] as num?)?.toInt();
    if (days != null && days > 0) {
      return '${l10n.mailboxRewardItem(itemName)} · ${l10n.mailboxRewardDays(days)}';
    }
    return l10n.mailboxRewardItem(itemName);
  }

  static String _shortDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final themeColors = context.watch<GameService>().themeGradient;

    return Scaffold(
      resizeToAvoidBottomInset: kIsWeb ? false : null,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: themeColors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      color: const Color(0xFF8A7A72),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.mark_email_unread,
                      color: Color(0xFFEF6C00),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.mailboxTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF5A4038),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Consumer<GameService>(
                  builder: (context, game, _) {
                    _drainReward(game);
                    if (game.mailboxLoading && game.mailbox.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (game.mailbox.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.mail_outline,
                              size: 46,
                              color: Color(0xFFBCAAA4),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l10n.mailboxEmpty,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A7A72),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.mailboxEmptyHint,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFFA1887F),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      itemCount: game.mailbox.length,
                      itemBuilder: (_, i) =>
                          _letter(game, game.mailbox[i], l10n),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _letter(GameService game, Map<String, dynamic> mail, L10n l10n) {
    final id = (mail['id'] as num).toInt();
    final unread = mail['read_at'] == null;
    final claimed = mail['claimed_at'] != null;
    final rewardLabel = _rewardLabel(l10n, mail);
    final hasReward = rewardLabel.isNotEmpty;
    final expiresAt = parseServerUtc(mail['expires_at']);
    final expired = expiresAt != null && expiresAt.isBefore(DateTime.now());
    final sentAt = parseServerUtc(mail['created_at']);
    final sender = (mail['sender_name'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(16),
        border: unread
            ? Border.all(color: const Color(0xFFEF6C00), width: 1.4)
            : null,
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          // Opening the letter is what marks it read — the same gesture a
          // person would call "reading it".
          onExpansionChanged: (open) {
            if (open && unread) game.markMailRead(id);
          },
          title: Row(
            children: [
              if (unread)
                Container(
                  margin: const EdgeInsets.only(right: 7),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF6C00),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    l10n.mailboxUnreadBadge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  (mail['title'] ?? '').toString(),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                    color: const Color(0xFF5A4038),
                  ),
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              [
                // A letter can name its own sender — an event, a person —
                // otherwise it comes from the team, in the reader's language.
                sender.isEmpty ? l10n.mailboxFrom : sender,
                if (sentAt != null) _shortDate(sentAt),
              ].join(' · '),
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFA1887F)),
            ),
          ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                (mail['body'] ?? '').toString(),
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.65,
                  color: Color(0xFF5A4038),
                ),
              ),
            ),
            if (hasReward) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.card_giftcard,
                      size: 20,
                      color: Color(0xFFEF6C00),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            rewardLabel,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF5A4038),
                            ),
                          ),
                          if (expiresAt != null && !claimed)
                            Text(
                              l10n.mailboxExpiresAt(_shortDate(expiresAt)),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: expired
                                    ? const Color(0xFFC62828)
                                    : const Color(0xFFA1887F),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (claimed)
                      _stateChip(l10n.mailboxClaimed, const Color(0xFF2E7D32))
                    else if (expired)
                      _stateChip(l10n.mailboxExpired, const Color(0xFF8A7A72))
                    else
                      ElevatedButton(
                        onPressed: _claiming == id
                            ? null
                            : () => _claim(game, id),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF6C00),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 9,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          l10n.mailboxClaim,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stateChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
    ),
  );
}
