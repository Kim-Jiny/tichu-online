import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show pendingCampaignTaps, pendingPushOpens;
import '../services/game_service.dart';
import '../theme/cartoon.dart';

/// Whether to raise the first-time consent popup here.
///
/// Never on the web. Web builds skip FCM registration entirely, so there is no
/// token and a yes would buy the player nothing — it would just cost the web
/// funnel a popup. Leaving the question unanswered is the point:
/// marketing_asked_at stays null, and the app asks properly on whichever
/// device they eventually install it on.
bool marketingConsentAskAllowed({required bool isWeb}) => !isWeb;

/// Whether to show the two-yearly confirmation here.
///
/// Everywhere, web included — the opposite of the rule above, on purpose. This
/// notice is owed to someone who already consented (정보통신망법 §50 ⑧), and a
/// player who has stopped opening the app may only ever be reachable in a
/// browser. Suppressing it there would mean the obligation goes undischarged
/// for exactly the people hardest to reach.
bool marketingConfirmNoticeAllowed({required bool isWeb}) => true;

/// The two things a marketing campaign needs on screen: asking permission
/// once, and saying what arrived when a notification is tapped.
///
/// Wrapped around the lobby rather than added to its initState. Both of these
/// are triggered by state that shows up after the first frame — consent needs
/// a completed login, and a reward can land seconds later when a cold-start
/// tap finally reaches the server — so they need something watching, not a
/// one-shot at mount.
class MarketingPushGate extends StatefulWidget {
  final Widget child;

  const MarketingPushGate({super.key, required this.child});

  @override
  State<MarketingPushGate> createState() => _MarketingPushGateState();
}

class _MarketingPushGateState extends State<MarketingPushGate> {
  /// One popup at a time, and never twice for the same launch.
  bool _askingConsent = false;
  bool _showingReward = false;

  @override
  void initState() {
    super.initState();
    // A tap while the app is backgrounded changes nothing else — the socket
    // stays up, no state moves — so without listening here the queued campaign
    // would sit unread until something unrelated happened to rebuild this.
    pendingCampaignTaps.addListener(_onTap);
    pendingPushOpens.addListener(_onTap);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    pendingCampaignTaps.removeListener(_onTap);
    pendingPushOpens.removeListener(_onTap);
    super.dispose();
  }

  void _onTap() {
    if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    final game = context.read<GameService>();

    // Notifications tapped before GameService existed. Handing them over is
    // idempotent — the server pays once — so no bookkeeping is needed beyond
    // clearing the set.
    if (pendingCampaignTaps.value.isNotEmpty && game.playerId.isNotEmpty) {
      for (final id in pendingCampaignTaps.value) {
        game.claimPushReward(id);
      }
      pendingCampaignTaps.value = const [];
    }

    // Taps on notifications that pay nothing. Purely a statistic, so it is
    // fire-and-forget: the queue is cleared whether or not the socket is up,
    // because a lost open is worth less than a queue that grows forever.
    if (pendingPushOpens.value.isNotEmpty && game.playerId.isNotEmpty) {
      for (final open in pendingPushOpens.value) {
        game.reportPushOpened(open.kind, open.id);
      }
      pendingPushOpens.value = const [];
    }

    // The reward comes first. Someone who just tapped a notification is
    // holding the phone waiting to see what they got; a consent popup in front
    // of that reads as the app ignoring them.
    if (game.pendingPushReward != null && !_showingReward) {
      _showReward(game);
      return;
    }
    if (_askingConsent || _showingReward || game.playerId.isEmpty) return;
    if (!game.marketingAsked) {
      if (marketingConsentAskAllowed(isWeb: kIsWeb)) _askConsent(game);
    } else if (game.marketingConfirmDue &&
        marketingConfirmNoticeAllowed(isWeb: kIsWeb)) {
      _confirmConsent(game);
    }
  }

  Future<void> _showReward(GameService game) async {
    final reward = game.pendingPushReward;
    if (reward == null) return;
    _showingReward = true;
    // Cleared before the dialog rather than after: the dialog awaits a tap,
    // and a rebuild in the meantime would see the same reward still pending
    // and open a second copy.
    game.consumePushReward();
    await showPushRewardDialog(context, reward);
    _showingReward = false;
    if (mounted) _sync();
  }

  /// The two-yearly notice. Reuses the consent flag as its guard — only one of
  /// the two ever applies, and they must not stack.
  Future<void> _confirmConsent(GameService game) async {
    _askingConsent = true;
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          _ConfirmConsentDialog(consentAt: game.marketingConsentAt),
    );
    if (answer != null) game.confirmMarketingConsent(answer);
    _askingConsent = false;
  }

  Future<void> _askConsent(GameService game) async {
    _askingConsent = true;
    final answer = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _ConsentDialog(),
    );
    // A dismissal that somehow got through is not an answer — leave the
    // question open rather than recording a "no" nobody gave.
    if (answer != null) game.setMarketingConsent(answer);
    _askingConsent = false;
  }

  @override
  Widget build(BuildContext context) {
    // Watches so a reward arriving or a login completing runs _sync again.
    context.watch<GameService>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    return widget.child;
  }
}

/// 마케팅 팝업 공통 틀: 카툰 패널 모양의 팝업.
AlertDialog _marketingShell({
  Widget? title,
  required Widget content,
  required List<Widget> actions,
}) {
  return AlertDialog(
    backgroundColor: Cartoon.paper,
    surfaceTintColor: Colors.transparent,
    scrollable: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(26),
      side: const BorderSide(color: Cartoon.ink, width: 2.5),
    ),
    titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
    contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
    actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
    title: title,
    content: content,
    actions: actions,
  );
}

Widget _marketingButton(String label, VoidCallback onTap, {Color? color}) {
  return CartoonButton(
    expand: false,
    height: 46,
    color: color ?? Cartoon.orange,
    onPressed: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: CartoonButton.label(label, size: 18),
    ),
  );
}

Widget _marketingGhost(String label, VoidCallback onTap) {
  return TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      foregroundColor: Cartoon.ink.withValues(alpha: 0.6),
    ),
    child: Text(label, style: Cartoon.text(size: 17)),
  );
}

Widget _marketingTitle(Widget leading, String text) {
  return Row(
    children: [
      leading,
      const SizedBox(width: 12),
      Expanded(child: Text(text, style: Cartoon.text(size: 22, height: 1.15))),
    ],
  );
}

/// Asks for marketing consent, once.
///
/// Opt-in, with declining as the plainly available answer rather than a
/// greyed-out afterthought: consent that was hard to refuse is not consent,
/// and 정보통신망법 wants an affirmative choice on the record either way.
class _ConsentDialog extends StatelessWidget {
  const _ConsentDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return _marketingShell(
      title: _marketingTitle(
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Cartoon.yellow,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Cartoon.ink, width: 2),
          ),
          child: const Icon(
            Icons.campaign_rounded,
            size: 28,
            color: Cartoon.ink,
          ),
        ),
        l10n.marketingConsentTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.marketingConsentBody,
            style: Cartoon.text(size: 16.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: Cartoon.cream,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              l10n.marketingConsentNote,
              style: Cartoon.text(
                size: 13.5,
                height: 1.45,
                color: Cartoon.ink.withValues(alpha: 0.65),
              ),
            ),
          ),
        ],
      ),
      actions: [
        _marketingGhost(
          l10n.marketingConsentDecline,
          () => Navigator.pop(context, false),
        ),
        _marketingButton(
          l10n.marketingConsentAccept,
          () => Navigator.pop(context, true),
          color: Cartoon.green,
        ),
      ],
    );
  }
}

/// Show what a tapped campaign notification paid out.
///
/// Public so it can be pumped in a test: this dialog IS the confirmation that
/// the notification did something, and gold arriving silently in the wallet is
/// indistinguishable from a notification that did nothing at all.
Future<void> showPushRewardDialog(
  BuildContext context,
  PushRewardOutcome reward,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PushRewardDialog(reward: reward),
  );
}

/// The two-yearly confirmation that someone is still subscribed to marketing
/// messages — 정보통신망법 §50 ⑧.
///
/// 시행령 §62-3 fixes what it has to say, and each line below is one of those
/// items: who is sending (전송자의 명칭), the date consent was given and the
/// fact of it (수신동의 날짜 및 사실), and how to keep or withdraw it
/// (유지 또는 철회의 의사표시 방법). Withdrawing is a button here, not a
/// pointer to a settings screen — the notice itself has to be actionable.
class _ConfirmConsentDialog extends StatelessWidget {
  final DateTime? consentAt;

  const _ConfirmConsentDialog({this.consentAt});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final d = consentAt;
    final dateText = d == null
        ? '-'
        : '${d.year}. ${d.month.toString().padLeft(2, '0')}. '
              '${d.day.toString().padLeft(2, '0')}.';
    return _marketingShell(
      title: _marketingTitle(
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Cartoon.blue.withValues(alpha: 1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Cartoon.ink, width: 2),
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            size: 26,
            color: Colors.white,
          ),
        ),
        l10n.marketingConfirmTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.marketingConfirmBody,
            style: Cartoon.text(size: 16.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Cartoon.cream,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _line(
                  l10n.marketingConfirmSenderLabel,
                  l10n.marketingSenderName,
                ),
                const SizedBox(height: 6),
                _line(l10n.marketingConfirmDateLabel, dateText),
                const SizedBox(height: 6),
                _line(
                  l10n.marketingConfirmStatusLabel,
                  l10n.marketingConfirmStatusValue,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        _marketingGhost(
          l10n.marketingConfirmStop,
          () => Navigator.pop(context, false),
        ),
        _marketingButton(
          l10n.marketingConfirmKeep,
          () => Navigator.pop(context, true),
          color: Cartoon.green,
        ),
      ],
    );
  }

  static Widget _line(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 80,
        child: Text(
          label,
          style: Cartoon.text(
            size: 14,
            color: Cartoon.ink.withValues(alpha: 0.55),
          ),
        ),
      ),
      Expanded(child: Text(value, style: Cartoon.text(size: 14.5))),
    ],
  );
}

/// "You got 50 gold." Gold lands silently in the wallet, so without this the
/// notification they tapped appears to have done nothing.
class PushRewardDialog extends StatelessWidget {
  final PushRewardOutcome reward;

  const PushRewardDialog({super.key, required this.reward});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final gold = reward.gold ?? 0;
    final isGold = reward.rewardType == 'gold' && gold > 0;
    return _marketingShell(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Cartoon.yellow,
              shape: BoxShape.circle,
              border: Border.all(color: Cartoon.ink, width: 2.5),
            ),
            child: Icon(
              isGold ? Icons.savings_rounded : Icons.card_giftcard_rounded,
              size: 40,
              color: Cartoon.ink,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.pushRewardTitle,
            textAlign: TextAlign.center,
            style: Cartoon.text(size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            isGold ? l10n.pushRewardGold(gold) : l10n.pushRewardItem,
            textAlign: TextAlign.center,
            style: Cartoon.text(size: 17, height: 1.45),
          ),
        ],
      ),
      actions: [
        CartoonButton(
          height: 50,
          onPressed: () => Navigator.pop(context),
          child: CartoonButton.label(l10n.commonConfirm, size: 19),
        ),
      ],
    );
  }
}
