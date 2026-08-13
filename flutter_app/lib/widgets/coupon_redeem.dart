import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/game_service.dart';

/// Whether this build may show any coupon UI at all.
///
/// Everywhere except the iOS app. Redeeming a code for gold is close enough to
/// a purchase flow that App Review can read it as one, so the iOS build shows
/// nothing about coupons — not the entry field, not the code on a notice.
/// iOS Safari is a web client and is unaffected: `kIsWeb` is checked first.
///
/// This is a display rule, not a security rule. The server takes a redemption
/// from anyone who is logged in, because a rule enforced by hiding a button is
/// not enforced at all — and the same account can always use the web.
bool get couponUiVisible =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;

/// The redeem dialog. Returns true when something was actually granted.
Future<bool> showCouponRedeemDialog(
  BuildContext context, {
  String? presetCode,
}) async {
  final granted = await showDialog<bool>(
    context: context,
    builder: (ctx) => _CouponRedeemDialog(presetCode: presetCode),
  );
  return granted ?? false;
}

class _CouponRedeemDialog extends StatefulWidget {
  final String? presetCode;

  const _CouponRedeemDialog({this.presetCode});

  @override
  State<_CouponRedeemDialog> createState() => _CouponRedeemDialogState();
}

class _CouponRedeemDialogState extends State<_CouponRedeemDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.presetCode ?? '');
  bool _busy = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _rewardLine(L10n l10n, CouponOutcome out) {
    if (out.rewardType == 'gold') {
      return l10n.couponRewardGold(out.rewardGold ?? 0);
    }
    final days = out.rewardDays;
    // A permanent item has no expiry, and "for 0 days" would be a lie.
    return days == null || days <= 0
        ? l10n.couponRewardItem
        : l10n.couponRewardItemDays(days);
  }

  Future<void> _submit() async {
    final l10n = L10n.of(context);
    final code = _controller.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final game = context.read<GameService>();
    final out = await game.redeemCoupon(code);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (out.success) {
        _success = _rewardLine(l10n, out);
      } else {
        // A silent timeout has no server message of its own.
        _error = out.message ?? l10n.commonError;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final done = _success != null;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.confirmation_number_outlined,
              size: 20, color: Color(0xFF6A5A52)),
          const SizedBox(width: 8),
          Text(
            l10n.couponRedeemTitle,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3E312A),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (done) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFF66BB6A), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _success!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3E312A),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.couponCodeLabel,
                  hintText: 'WELCOME2026',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _error,
                  errorMaxLines: 3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.couponRedeemHint,
                style: const TextStyle(fontSize: 12, color: Color(0xFF9A8E8A)),
              ),
            ],
          ],
        ),
      ),
      actions: done
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.commonConfirm),
              ),
            ]
          : [
              TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.couponRedeemButton),
              ),
            ],
    );
  }
}

/// What the iOS app shows instead of the coupon block.
///
/// The code, the field and any "go to the web" prompt stay off — that last one
/// is the external call-to-action the whole gate exists to avoid. What is left
/// is the bare fact that this post carries a coupon, so a reader who wants one
/// knows there is something to ask about. Without this the iOS build hides the
/// coupon so completely that nobody could know to ask, and support-by-inquiry
/// has nothing to work with.
class NoticeCouponMuted extends StatelessWidget {
  const NoticeCouponMuted({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F2EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6DDD8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.confirmation_number_outlined,
              size: 15, color: Color(0xFF9A8E8A)),
          const SizedBox(width: 6),
          Text(
            l10n.couponInNotice,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A7A72),
            ),
          ),
        ],
      ),
    );
  }
}

/// The coupon attached to a notice: the code, a way to copy it, and the way in.
///
/// Callers must check [couponUiVisible] first — this widget draws the code
/// itself, which is the part the iOS build must not show.
class NoticeCouponBlock extends StatelessWidget {
  final String code;

  const NoticeCouponBlock({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF6E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3D9AE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.confirmation_number,
                  size: 16, color: Color(0xFFB07B2E)),
              const SizedBox(width: 6),
              Text(
                l10n.couponSectionTitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB07B2E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  code,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Color(0xFF5A4038),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.couponCopied,
                icon: const Icon(Icons.copy_rounded, size: 18),
                color: const Color(0xFF8A7A72),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(content: Text(l10n.couponCopied)),
                    );
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => showCouponRedeemDialog(context, presetCode: code),
              icon: const Icon(Icons.redeem, size: 18),
              label: Text(l10n.couponRedeemButton),
            ),
          ),
        ],
      ),
    );
  }
}
