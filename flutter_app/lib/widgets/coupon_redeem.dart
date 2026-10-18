import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../theme/cartoon.dart';
import '../services/game_service.dart';
import 'cartoon_icons.dart';

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

/// 쿠폰 아이콘 — 직접 그린 카툰 티켓(별 + 점선), [Icon] 과 같은 크기 규칙.
///
/// 예전에는 검은 바탕을 지운 webp 그림을 썼다. 벡터로 바꾼 건 다른 카툰 아이콘(룰북·자물쇠
/// 등)과 선 굵기·색을 맞추고, 어느 크기에서도 선명하게 하려는 것이다.
Widget couponIcon({double size = 20, double opacity = 1}) {
  final icon = CouponGlyph(size: size);
  return opacity >= 1 ? icon : Opacity(opacity: opacity, child: icon);
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

/// 입력하는 대로 대문자로 바꾸고 공백(복사하다 딸려 온 띄어쓰기·줄바꿈)은 뺀다.
/// 서버도 같은 규칙으로 정규화하지만(normalizeCouponCode), 화면에서 먼저 정리해
/// 보이는 글자와 실제로 보내는 글자가 같게 한다.
class _CouponCodeFormatter extends TextInputFormatter {
  const _CouponCodeFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (cleaned == newValue.text) return newValue;
    // 지운 글자 수만큼 커서를 당긴다.
    final removed = newValue.text.length - cleaned.length;
    final offset = (newValue.selection.baseOffset - removed).clamp(
      0,
      cleaned.length,
    );
    return TextEditingValue(
      text: cleaned,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

class _CouponRedeemDialogState extends State<_CouponRedeemDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller = TextEditingController(
    text: widget.presetCode == null
        ? ''
        : widget.presetCode!.replaceAll(RegExp(r'\s+'), '').toUpperCase(),
  );
  // 틀렸을 때 입력 칸이 좌우로 떨린다.
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _busy = false;
  String? _error;
  String? _success;
  int _burst = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      // 고치기 시작하면 이전 오류는 지운다.
      if (_error != null && mounted) setState(() => _error = null);
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _shake.dispose();
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
    if (_busy) return;
    if (code.isEmpty) {
      setState(() => _error = l10n.couponEnterCode);
      _shake.forward(from: 0);
      return;
    }
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
        _burst++;
      } else {
        // A silent timeout has no server message of its own.
        _error = out.message ?? l10n.commonError;
      }
    });
    if (!out.success) _shake.forward(from: 0);
  }

  /// 클립보드의 코드를 입력 칸에 넣는다(공백·소문자는 정리).
  Future<void> _paste() async {
    final l10n = L10n.of(context);
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = (data?.text ?? '')
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (text.isEmpty) {
      setState(() => _error = l10n.couponClipboardEmpty);
      _shake.forward(from: 0);
      return;
    }
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final done = _success != null;
    final hasText = _controller.text.trim().isNotEmpty;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Stack(
          children: [
            SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: Cartoon.panelDecoration(radius: 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CartoonFloat(amplitude: 3, child: couponIcon(size: 36)),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            done
                                ? l10n.couponRedeemedTitle
                                : l10n.couponRedeemTitle,
                            style: Cartoon.text(size: 23),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (done) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Cartoon.surface(const Color(0xFFFFF1C9)),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Cartoon.ink, width: 1.8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF3DBE6A),
                              size: 30,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _success!,
                                style: Cartoon.userText(
                                  size: 16,
                                  weight: FontWeight.w800,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      CartoonButton(
                        height: 50,
                        color: Cartoon.green,
                        onPressed: () => Navigator.pop(context, true),
                        child: CartoonButton.label(
                          l10n.commonConfirm,
                          size: 19,
                        ),
                      ),
                    ] else ...[
                      // 코드 입력 칸: 쿠폰 티켓처럼 크림색 바탕에 큰 글자.
                      AnimatedBuilder(
                        animation: _shake,
                        builder: (context, child) {
                          final t = _shake.value;
                          final dx = t == 0
                              ? 0.0
                              : math.sin(t * math.pi * 6) * 9 * (1 - t);
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                          decoration: BoxDecoration(
                            color: Cartoon.surface(const Color(0xFFFFF8E6)),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _error != null ? Cartoon.red : Cartoon.ink,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.couponCodeLabel,
                                style: Cartoon.text(
                                  size: 13,
                                  color: Cartoon.ink.withValues(alpha: 0.6),
                                ),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _controller,
                                      autofocus: true,
                                      enabled: !_busy,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      textInputAction: TextInputAction.done,
                                      autocorrect: false,
                                      enableSuggestions: false,
                                      inputFormatters: const [
                                        _CouponCodeFormatter(),
                                      ],
                                      onSubmitted: (_) => _submit(),
                                      cursorColor: Cartoon.orangeDeep,
                                      // 입력한 글자는 진한 굵은 고정폭, 예시 글자는 연하고 기울임 —
                                      // 예시가 이미 채워진 코드로 보여 그대로 등록을 누르는 일이 없게.
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 2.5,
                                        color: Cartoon.ink,
                                      ),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        disabledBorder: InputBorder.none,
                                        filled: false,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                        hintText: 'WELCOME2026',
                                        hintStyle: TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 18,
                                          fontWeight: FontWeight.w400,
                                          fontStyle: FontStyle.italic,
                                          letterSpacing: 1.6,
                                          color: Cartoon.ink.withValues(
                                            alpha: 0.25,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 글자가 있으면 지우기, 없으면 붙여넣기.
                                  if (hasText)
                                    _miniButton(
                                      Icons.close_rounded,
                                      l10n.couponClearCode,
                                      _busy ? null : _controller.clear,
                                    )
                                  else
                                    _miniButton(
                                      Icons.content_paste_rounded,
                                      l10n.couponPaste,
                                      _busy ? null : _paste,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 160),
                        alignment: Alignment.topCenter,
                        child: _error == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_rounded,
                                      size: 17,
                                      color: Cartoon.red,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: Cartoon.userText(
                                          size: 13,
                                          weight: FontWeight.w700,
                                          color: const Color(0xFFD64550),
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        l10n.couponRedeemHint,
                        textAlign: TextAlign.center,
                        style: Cartoon.userText(
                          size: 12,
                          weight: FontWeight.w600,
                          color: Cartoon.ink.withValues(alpha: 0.55),
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CartoonButton(
                              height: 48,
                              color: const Color(0xFF9AA5B1),
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.pop(context, false),
                              child: CartoonButton.label(
                                l10n.commonCancel,
                                size: 17,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: CartoonButton(
                              height: 48,
                              color: Cartoon.orange,
                              onPressed: (_busy || !hasText) ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : CartoonButton.label(
                                      l10n.couponRedeemButton,
                                      size: 19,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // 등록에 성공하면 색종이.
            if (_burst > 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: CartoonConfetti(
                    key: ValueKey('coupon-burst-$_burst'),
                    seed: _burst,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 입력 칸 오른쪽의 작은 둥근 버튼(지우기·붙여넣기).
  Widget _miniButton(IconData icon, String tooltip, VoidCallback? onTap) {
    return Semantics(
      button: true,
      label: tooltip,
      child: CartoonPressable(
        scale: 0.88,
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: onTap == null ? const Color(0xFFE6DFD6) : Cartoon.yellow,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Cartoon.ink, width: 1.8),
          ),
          child: Icon(icon, size: 21, color: Cartoon.ink),
        ),
      ),
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
            border: Border.all(color: Cartoon.ink, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
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
              shadowOffset: 2.5,
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
                              border: Border.all(
                                color: Cartoon.ink,
                                width: 1.5,
                              ),
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
                          color: Cartoon.paper,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Cartoon.ink, width: 1.6),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                code,
                                maxLines: 1,
                                style: TextStyle(
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
                                    width: 1.6,
                                  ),
                                ),
                                child: Icon(
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
