import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../theme/cartoon.dart';
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

  String _rewardLine(BuildContext context, L10n l10n, CouponOutcome out) {
    if (out.rewardType == 'gold') {
      return l10n.couponRewardGold(out.rewardGold ?? 0);
    }
    final days = out.rewardDays;
    // Same locale-fallback rule the shop uses for item names: this language,
    // else Korean.
    final locale = Localizations.localeOf(context).languageCode;
    final name = switch (locale) {
      'en' => out.rewardItemNameEn,
      'de' => out.rewardItemNameDe,
      _ => out.rewardItemNameKo,
    };
    // Older servers (or a reward shape we didn't expect) leave the name
    // blank — fall back to the old unnamed copy rather than showing "".
    if (name == null || name.isEmpty) {
      return days == null || days <= 0
          ? l10n.couponRewardItem
          : l10n.couponRewardItemDays(days);
    }
    // A permanent item has no expiry, and "for 0 days" would be a lie.
    return days == null || days <= 0
        ? l10n.couponRewardItemNamed(name)
        : l10n.couponRewardItemNamedDays(name, days);
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
        _success = _rewardLine(context, l10n, out);
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
      title: Row(
        children: [
          couponIcon(size: 22),
          const SizedBox(width: 8),
          Text(l10n.couponRedeemTitle, style: Cartoon.text(size: 21)),
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

/// 공지 목록에서 "쿠폰이 들어 있는 글" 표시. 노란 티켓 모양 알약이 살짝 기울어
/// 숨 쉬듯 움직여서, 작은 아이콘보다 먼저 눈에 띈다. 코드는 iOS 에서 가려지지만
/// 이 표시는 어디서나 보인다 — 어떤 글에 쿠폰이 있는지 아는 것도 정보다.
class CouponTag extends StatelessWidget {
  const CouponTag({super.key});

  @override
  Widget build(BuildContext context) {
    return CartoonPulse(
      amount: 0.06,
      child: Transform.rotate(
        angle: -0.07,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 3, 9, 3),
          decoration: BoxDecoration(
            color: Cartoon.yellow,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Cartoon.ink, width: 2),
            boxShadow: const [
              BoxShadow(color: Cartoon.ink, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.confirmation_number_rounded,
                size: 15,
                color: Cartoon.ink,
              ),
              const SizedBox(width: 3),
              Text(
                L10n.of(context).couponSectionTitle,
                style: Cartoon.text(size: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 공지 상세에 붙는 쿠폰 티켓: 위에 "쿠폰" 리본, 가운데 코드(복사 버튼), 점선 아래
/// 등록 버튼. 자르는 모양(clip) 대신 테두리 있는 카드로 — 테두리와 그림자가
/// 잘려 나가지 않게.
class NoticeCouponBlock extends StatelessWidget {
  final String code;

  const NoticeCouponBlock({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final canRedeem = couponRedeemAllowed;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: CartoonEntrance(
          from: const Offset(0, 24),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            decoration: Cartoon.panelDecoration(
              color: const Color(0xFFFFF1C9),
              radius: 22,
              shadowOffset: 4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Cartoon.orange,
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: Cartoon.ink, width: 2),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.confirmation_number_rounded,
                                  size: 17,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 5),
                                Cartoon.outlinedText(
                                  l10n.couponSectionTitle,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          CartoonFloat(
                            amplitude: 3,
                            child: couponIcon(size: 30),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 코드는 읽고, 복사하고, 입력하는 유일한 것 — 따로 틀을 둔다.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Cartoon.ink, width: 2.2),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                code,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.5,
                                  color: Cartoon.ink,
                                ),
                              ),
                            ),
                            CartoonPressable(
                              scale: 0.88,
                              onTap: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: code),
                                );
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    SnackBar(content: Text(l10n.couponCopied)),
                                  );
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: Cartoon.yellow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Cartoon.ink,
                                    width: 2.2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Cartoon.ink,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.copy_rounded,
                                  size: 20,
                                  color: Cartoon.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 떼어 낼 곳이 없으면(iOS 앱) 점선도 버튼도 두지 않는다.
                if (canRedeem) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: _DashedLine(
                      color: Cartoon.ink.withValues(alpha: 0.4),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: CartoonButton(
                      height: 50,
                      color: Cartoon.green,
                      onPressed: () =>
                          showCouponRedeemDialog(context, presetCode: code),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.redeem_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          const SizedBox(width: 6),
                          CartoonButton.label(
                            l10n.couponRedeemButton,
                            size: 18,
                          ),
                        ],
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
