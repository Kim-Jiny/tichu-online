import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show pendingCampaignTaps;
import '../services/game_service.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
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
    if (pendingCampaignTaps.isNotEmpty && game.playerId.isNotEmpty) {
      for (final id in pendingCampaignTaps.toList()) {
        game.claimPushReward(id);
      }
      pendingCampaignTaps.clear();
    }

    // The reward comes first. Someone who just tapped a notification is
    // holding the phone waiting to see what they got; a consent popup in front
    // of that reads as the app ignoring them.
    if (game.pendingPushReward != null && !_showingReward) {
      _showReward(game);
      return;
    }
    if (!_askingConsent &&
        !_showingReward &&
        game.playerId.isNotEmpty &&
        !game.marketingAsked) {
      _askConsent(game);
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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      backgroundColor: const Color(0xFFFDFBFA),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1D6),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              size: 20,
              color: Color(0xFFE08A1E),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l10n.marketingConsentTitle,
              style: const TextStyle(
                fontSize: 17.5,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3E312A),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.marketingConsentBody,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: Color(0xFF5A4038),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F1EE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              l10n.marketingConsentNote,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: Color(0xFF8A7A72),
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            foregroundColor: const Color(0xFF8A7A72),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(l10n.marketingConsentDecline),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFE08A1E),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          child: Text(l10n.marketingConsentAccept),
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
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: const Color(0xFFFDFBFA),
      contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF4DC),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGold ? Icons.savings_rounded : Icons.card_giftcard_rounded,
              size: 34,
              color: const Color(0xFFE0A21E),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.pushRewardTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3E312A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isGold ? l10n.pushRewardGold(gold) : l10n.pushRewardItem,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Color(0xFF5A4038),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE08A1E),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              textStyle: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(l10n.commonConfirm),
          ),
        ),
      ],
    );
  }
}
