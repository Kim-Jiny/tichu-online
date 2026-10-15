import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import '../theme/cartoon.dart';
import '../utils/gold_format.dart';
import '../utils/mail_status.dart';
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
  // 보상을 받을 때마다 올려서 색종이를 새로 터뜨린다.
  int _burst = 0;

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

  /// 받을 보상이 남아 있는 우편인가 (보상 있음 · 아직 안 받음 · 만료 전).
  bool _canClaim(Map<String, dynamic> mail) {
    final gold = (mail['reward_gold'] as num?)?.toInt() ?? 0;
    final hasItem = (mail['reward_item_key'] ?? '').toString().isNotEmpty;
    if (gold <= 0 && !hasItem) return false;
    if (mail['claimed_at'] != null) return false;
    final exp = parseServerUtc(mail['expires_at']);
    return exp == null || !exp.isBefore(DateTime.now());
  }

  /// 한꺼번에 받기: 서버에는 한 통씩 차례로 보낸다.
  Future<void> _claimAll(GameService game, List<int> ids) async {
    for (final id in ids) {
      if (!mounted) return;
      _claim(game, id);
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  }

  void _claim(GameService game, int id) {
    setState(() => _claiming = id);
    game.claimMail(id);
  }

  /// A claim's outcome arrives as a message, not a reply, so the result is
  /// picked up on the next rebuild rather than awaited.
  ///
  /// 실패도 결과로 받는다. 만료됐거나, 이미 수령했거나, 다른 기기에서 먼저
  /// 가져간 우편은 정상적으로 실패한다 — 그걸 집어가지 않으면 버튼이
  /// '수령 중' 인 채로 굳어서 다시 눌러볼 수도 없다.
  void _drainClaimOutcome(GameService game) {
    final failed = game.takeFailedMailClaim();
    if (failed != null) {
      _claiming = null;
      final message = failed.message;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || message == null || message.isEmpty) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: const Color(0xFFB3261E),
            duration: const Duration(seconds: 2),
          ),
        );
      });
    }
    _drainReward(game);
  }

  void _drainReward(GameService game) {
    final reward = game.takeMailReward();
    if (reward == null) return;
    _claiming = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _burst++);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(L10n.of(context).mailboxClaimedToast),
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  /// Kept in step with the server's MAIL_RETENTION_DAYS. Shown to the player,
  /// so it is a promise: after this the letter is gone and its reward with it.
  static const int _retentionDays = 14;

  Future<void> _confirmDelete(GameService game, int id, L10n l10n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.mailboxDeleteConfirm),
        content: Text(l10n.mailboxDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.mailboxCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFC62828),
            ),
            child: Text(l10n.mailboxDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    game.deleteMail(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.mailboxDeleted),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _rewardLabel(L10n l10n, Map<String, dynamic> mail) {
    final gold = (mail['reward_gold'] as num?)?.toInt() ?? 0;
    if (gold > 0) return l10n.mailboxRewardGold(formatGold(gold));
    // 서버는 item_name_ko/_en/_de 를 다 내려준다. 늘 한국어를 집으면
    // 영어·독일어로 쓰는 사람 화면에 아이템 이름만 한국어로 섞인다.
    // 없는 번역은 한국어로, 그것도 없으면 키로 떨어진다.
    final locale = Localizations.localeOf(context).languageCode;
    final localised = mail['item_name_$locale'];
    final itemName =
        (localised ?? mail['item_name_ko'] ?? mail['reward_item_key'] ?? '')
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

    return Theme(
      data: cartoonTheme(Theme.of(context)),
      child: Scaffold(
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
            bottom: false,
            child: Column(
              children: [
                CartoonEntrance(
                  from: const Offset(0, -30),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Row(
                      children: [
                        CartoonPressable(
                          scale: 0.88,
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: Cartoon.paper,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Cartoon.ink, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Cartoon.ink,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: Cartoon.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Cartoon.outlinedText(
                            l10n.mailboxTitle,
                            size: 28,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Consumer<GameService>(
                    builder: (context, game, _) {
                      _drainClaimOutcome(game);
                      if (game.mailboxLoading && game.mailbox.isEmpty) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Cartoon.orange,
                            strokeWidth: 4,
                          ),
                        );
                      }
                      if (game.mailbox.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CartoonFloat(
                                amplitude: 8,
                                child: Image.asset(
                                  'assets/dragonIcon.webp',
                                  width: 96,
                                  height: 96,
                                  color: Colors.white.withValues(alpha: 0.35),
                                  colorBlendMode: BlendMode.modulate,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                l10n.mailboxEmpty,
                                style: Cartoon.text(size: 19),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                l10n.mailboxEmptyHint,
                                style: Cartoon.userText(
                                  size: 13.5,
                                  weight: FontWeight.w500,
                                  color: Cartoon.ink.withValues(alpha: 0.6),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }
                      final claimable = [
                        for (final m in game.mailbox)
                          if (_canClaim(m)) (m['id'] as num).toInt(),
                      ];
                      return Stack(
                        children: [
                          ListView.builder(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              0,
                              16,
                              24 + MediaQuery.viewPaddingOf(context).bottom,
                            ),
                            // 맨 앞은 "모두 받기"(받을 게 둘 이상일 때), 맨 뒤는 보관
                            // 기간 안내 — 규칙이지 열자마자 읽을 것은 아니다.
                            itemCount: game.mailbox.length + 2,
                            itemBuilder: (_, i) {
                              if (i == 0) {
                                if (claimable.length < 2) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: CartoonPulse(
                                    child: CartoonButton(
                                      height: 52,
                                      color: Cartoon.orange,
                                      onPressed: () =>
                                          _claimAll(game, claimable),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.card_giftcard_rounded,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 8),
                                          CartoonButton.label(
                                            '${l10n.mailboxClaimAll} (${claimable.length})',
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final idx = i - 1;
                              if (idx < game.mailbox.length) {
                                final mail = game.mailbox[idx];
                                return CartoonEntrance(
                                  key: ValueKey('mail-${mail['id']}'),
                                  delay: Duration(
                                    milliseconds: 40 * idx.clamp(0, 7),
                                  ),
                                  from: const Offset(0, 18),
                                  child: _letter(game, mail, l10n),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                                child: Text(
                                  l10n.mailboxRetention(_retentionDays),
                                  style: Cartoon.userText(
                                    size: 12,
                                    weight: FontWeight.w500,
                                    color: Cartoon.ink.withValues(alpha: 0.5),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              );
                            },
                          ),
                          if (_burst > 0)
                            Positioned.fill(
                              child: CartoonConfetti(
                                key: ValueKey('mail-burst-$_burst'),
                                seed: _burst,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _letter(GameService game, Map<String, dynamic> mail, L10n l10n) {
    final id = (mail['id'] as num).toInt();
    final unread = mail['read_at'] == null;
    final claimed = mail['claimed_at'] != null;
    // Read is not the same as done: a letter holding a reward keeps its
    // highlight until the reward is out of it.
    final pending = mailNeedsAttention(mail);
    final rewardLabel = _rewardLabel(l10n, mail);
    final hasReward = rewardLabel.isNotEmpty;
    final expiresAt = parseServerUtc(mail['expires_at']);
    final expired = expiresAt != null && expiresAt.isBefore(DateTime.now());
    final sentAt = parseServerUtc(mail['created_at']);
    final sender = (mail['sender_name'] ?? '').toString().trim();

    // Material, not a decorated Container: an ExpansionTile is a ListTile, and
    // a ListTile paints its highlight and ink splash onto the nearest Material
    // ancestor. A coloured box in between hides them — Flutter asserts about
    // exactly this — so the fill and the border live on the Material itself.
    final fill = unread ? const Color(0xFFFFF6DD) : Cartoon.paper;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Cartoon.ink, offset: Offset(0, 2.5)),
        ],
      ),
      child: Material(
        color: fill,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Cartoon.ink, width: 2),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 2,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            // Opening the letter is what marks it read — the same gesture a
            // person would call "reading it".
            onExpansionChanged: (open) {
              if (open && unread) game.markMailRead(id);
            },
            title: Row(
              children: [
                if (pending)
                  Container(
                    margin: const EdgeInsets.only(right: 7),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Cartoon.red,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Cartoon.ink, width: 1.5),
                    ),
                    // Says which of the two it is: still unopened, or opened
                    // and still holding something.
                    child: Text(
                      unread ? l10n.mailboxUnreadBadge : l10n.mailboxClaim,
                      style: Cartoon.text(size: 12, color: Colors.white),
                    ),
                  ),
                Expanded(
                  child: Text(
                    (mail['title'] ?? '').toString(),
                    style: Cartoon.userText(
                      size: 16,
                      weight: pending ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    [
                      // A letter can name its own sender — an event, a person —
                      // otherwise it comes from the team, in the reader's language.
                      sender.isEmpty ? l10n.mailboxFrom : sender,
                      if (sentAt != null) _shortDate(sentAt),
                    ].join(' · '),
                    style: Cartoon.userText(
                      size: 12,
                      weight: FontWeight.w500,
                      color: Cartoon.ink.withValues(alpha: 0.55),
                    ),
                  ),
                  // 보상이 든 편지는 펼치지 않아도 뭐가 들었는지 보인다.
                  if (hasReward && !claimed && !expired)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Cartoon.yellow,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Cartoon.ink, width: 1.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.card_giftcard_rounded,
                              size: 15,
                              color: Cartoon.ink,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                rewardLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Cartoon.userText(
                                  size: 12.5,
                                  weight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 한 번에 받기: 펼쳐서 버튼을 찾지 않아도 줄에서 바로.
            trailing: _canClaim(mail)
                ? CartoonButton(
                    expand: false,
                    height: 40,
                    radius: 14,
                    color: Cartoon.orange,
                    onPressed: _claiming == id ? null : () => _claim(game, id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: CartoonButton.label(l10n.mailboxClaim, size: 15),
                    ),
                  )
                : null,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  (mail['body'] ?? '').toString(),
                  style: Cartoon.userText(
                    size: 14.5,
                    weight: FontWeight.w500,
                    height: 1.65,
                  ),
                ),
              ),
              // Deleting is for letters you are done with: read, and with
              // nothing left inside. A letter still holding a reward keeps the
              // claim button instead — the server refuses that delete anyway,
              // and offering a button that will be refused is worse than not
              // offering it.
              if (!unread && (!hasReward || claimed || expired))
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _confirmDelete(game, id, l10n),
                    icon: const Icon(Icons.delete_outline, size: 17),
                    label: Text(l10n.mailboxDelete),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFA1887F),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              if (hasReward) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: Cartoon.cream,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Cartoon.ink, width: 1.6),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.card_giftcard_rounded,
                        size: 24,
                        color: Cartoon.orangeDeep,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rewardLabel,
                              style: Cartoon.userText(
                                size: 15,
                                weight: FontWeight.w900,
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
                        CartoonButton(
                          expand: false,
                          height: 44,
                          radius: 15,
                          color: Cartoon.orange,
                          onPressed: _claiming == id
                              ? null
                              : () => _claim(game, id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: CartoonButton.label(
                              l10n.mailboxClaim,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stateChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: Cartoon.ink, width: 1.5),
    ),
    child: Text(label, style: Cartoon.text(size: 13, color: color)),
  );
}
