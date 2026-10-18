import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/cartoon.dart';

/// 강제 업데이트 화면.
///
/// 이 버전 미만의 앱은 서버가 쓸 수 없게 막는다. 막힌 사람이 보는 첫 화면이라, 겁주는 경고
/// 대신 "새 버전이 나왔어요" 라는 반가운 소식처럼 — 귀여운 용, 짧은 설명, 큰 버튼 하나.
/// 웹에서는 설치할 게 없어서 새로고침이 곧 업데이트다(문구와 버튼이 다르다).
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({
    super.key,
    required this.isWeb,
    required this.onPressed,
  });

  final bool isWeb;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      body: CartoonBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CartoonEntrance(
                      from: const Offset(0, -40),
                      child: CartoonFloat(
                        amplitude: 7,
                        child: Image.asset(
                          'assets/dragon_full.webp',
                          width: 190,
                          height: 190,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    CartoonEntrance(
                      delay: const Duration(milliseconds: 160),
                      from: const Offset(0, -24),
                      child: Cartoon.outlinedText(
                        l10n.appForceUpdateTitle,
                        size: 30,
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    CartoonEntrance(
                      delay: const Duration(milliseconds: 320),
                      from: const Offset(0, 24),
                      child: CartoonPanel(
                        radius: 24,
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        child: Column(
                          children: [
                            Text(
                              // 웹: 새로고침이 곧 업데이트(페이지는 늘 최신 번들을 준다).
                              isWeb
                                  ? l10n.appForceUpdateBodyWeb
                                  : l10n.appForceUpdateBody,
                              textAlign: TextAlign.center,
                              style: Cartoon.userText(
                                size: 15.5,
                                weight: FontWeight.w700,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    CartoonEntrance(
                      delay: const Duration(milliseconds: 480),
                      from: const Offset(0, 30),
                      child: CartoonPulse(
                        amount: 0.03,
                        child: CartoonButton(
                          height: 58,
                          color: Cartoon.green,
                          onPressed: onPressed,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isWeb
                                    ? Icons.refresh_rounded
                                    : Icons.system_update_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(width: 8),
                              CartoonButton.label(
                                isWeb
                                    ? l10n.appForceUpdateButtonWeb
                                    : l10n.appForceUpdateButton,
                                size: 21,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      l10n.appForceUpdateLater,
                      textAlign: TextAlign.center,
                      style: Cartoon.userText(
                        size: 12.5,
                        weight: FontWeight.w700,
                        color: Cartoon.ink.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
