import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/game_service.dart';

/// Whether this build may offer to redeem a code.
///
/// Everywhere except the iOS app. What App Review objects to is a call to
/// action pointing at a transaction it does not run, so what comes off there
/// is the entry field, the redeem stub and the shop shortcut. Printing the
/// code is not that: nothing in the iOS build says where to use it, and the
/// reward is free rather than bought.
///
/// iOS Safari keeps everything — `kIsWeb` is checked first.
///
/// A display rule, not a security rule. The server accepts a redemption from
/// anyone logged in; a rule enforced by hiding a button is not enforced, and
/// the same account can always reach the web.
bool get couponRedeemAllowed =>
    kIsWeb || defaultTargetPlatform != TargetPlatform.iOS;

/// The coupon artwork, sized like an [Icon] of the same [size].
///
/// The master is drawn on a black field, so the shipped webp has that keyed
/// out — dropping the raw PNG onto the cream ticket would have put a black
/// square on it. See assets_src/README.md.
Widget couponIcon({double size = 20, double opacity = 1}) {
  return Opacity(
    opacity: opacity,
    child: Image.asset(
      'assets/icons/coupon.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    ),
  );
}

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
  late final TextEditingController _controller = TextEditingController(
    text: widget.presetCode ?? '',
  );
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
          couponIcon(size: 22),
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
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF66BB6A),
                    size: 22,
                  ),
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
                // Typed text is dark and monospaced; the placeholder is light
                // and italic. With both in the field's default style the
                // example read as a code already filled in, and people tapped
                // Redeem on it.
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                  color: Color(0xFF3E312A),
                ),
                decoration: InputDecoration(
                  labelText: l10n.couponCodeLabel,
                  hintText: 'WELCOME2026',
                  hintStyle: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    fontStyle: FontStyle.italic,
                    letterSpacing: 1.2,
                    color: const Color(0xFF3E312A).withValues(alpha: 0.28),
                  ),
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

/// A ticket: two panels with a perforated line between them.
///
/// The first attempt was a rounded beige card with the code inside, and it
/// read as a notice box rather than as something you tear off — which is the
/// whole point of a coupon. The shape does that work: notches bitten out of
/// both edges, a dashed line across, the code in monospace on the stub.
class _TicketClipper extends CustomClipper<Path> {
  /// Distance from the top to the perforation, where the notches sit.
  final double notchY;

  static const double notchRadius = 9;
  static const double radius = 16;

  _TicketClipper({required this.notchY});

  @override
  Path getClip(Size size) {
    final body = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(radius),
        ),
      );
    final bites = Path()
      ..addOval(Rect.fromCircle(center: Offset(0, notchY), radius: notchRadius))
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width, notchY),
          radius: notchRadius,
        ),
      );
    return Path.combine(PathOperation.difference, body, bites);
  }

  @override
  bool shouldReclip(covariant _TicketClipper old) => old.notchY != notchY;
}

class _DashedLine extends StatelessWidget {
  final Color color;

  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Drawn as a row of short bars rather than a painter: the count comes
        // from the measured width, so it never ends mid-dash.
        const dash = 5.0;
        const gap = 4.0;
        final count = (constraints.maxWidth / (dash + gap)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => SizedBox(
              width: dash,
              height: 1.4,
              child: DecoratedBox(decoration: BoxDecoration(color: color)),
            ),
          ),
        );
      },
    );
  }
}

/// The coupon attached to a notice: the code, a way to copy it, and the way in.
///
/// Shown on every platform: only the stub below the perforation is gated, on
/// [couponRedeemAllowed].
class NoticeCouponBlock extends StatelessWidget {
  final String code;

  const NoticeCouponBlock({super.key, required this.code});

  /// Where the perforation sits, measured from the top of the ticket. Has to
  /// match the height of everything above it — the clipper cannot ask the
  /// children how tall they are, so the two are kept in step by hand.
  static const double _notchY = 116;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    const ink = Color(0xFF7A5B25);
    const line = Color(0xFFE3C48C);
    final canRedeem = couponRedeemAllowed;

    return Center(
      // Left to itself this stretched to the full width of a browser window
      // and stopped looking like a thing you tear off.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: ClipPath(
          clipper: canRedeem
              ? _TicketClipper(notchY: _notchY)
              : const _PlainClipper(),
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF8EC), Color(0xFFFDEFD6)],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: _notchY,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.local_activity_rounded,
                              size: 15,
                              color: ink,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              l10n.couponSectionTitle,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: ink,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // The code sits in its own outlined slot: it is the
                        // one thing on here to read, copy and type.
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: line),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: SelectableText(
                                  code,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2.5,
                                    color: Color(0xFF4E3A1C),
                                  ),
                                ),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: code),
                                  );
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context)
                                    ..hideCurrentSnackBar()
                                    ..showSnackBar(
                                      SnackBar(
                                        content: Text(l10n.couponCopied),
                                      ),
                                    );
                                },
                                child: const Padding(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.copy_rounded,
                                    size: 17,
                                    color: ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // No stub where there is nothing to tear off. Notches around an
                // empty strip read as a rendering fault, not as a design.
                if (canRedeem) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: _DashedLine(color: line),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFB07B2E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () =>
                            showCouponRedeemDialog(context, presetCode: code),
                        icon: const Icon(Icons.redeem_rounded, size: 17),
                        label: Text(
                          l10n.couponRedeemButton,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The ticket with no stub: a plain rounded card.
class _PlainClipper extends CustomClipper<Path> {
  const _PlainClipper();

  @override
  Path getClip(Size size) => Path()
    ..addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(_TicketClipper.radius),
      ),
    );

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
