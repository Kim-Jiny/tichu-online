import 'package:flutter/material.dart';

/// What colour of text will read on top of an equipped banner.
///
/// [override] is the admin-set `metadata.visual.text.color`, which is the
/// answer whenever it exists — someone looked at that banner and decided. It
/// often doesn't: the banners that shipped before that field, and anything an
/// admin adds without filling it in. Falling back to the popup's usual dark
/// brown puts near-invisible text on the dark banners, so the fallback is
/// decided by how bright the gradient actually is.
///
/// The whole gradient is averaged rather than sampled at one end. A banner
/// that runs dark-to-light has no single answer, and the header spans all of
/// it; the average is the colour most of the text sits on.
/// 밝은 배너 위에 쓰는 글자색.
const Color bannerInkDark = Color(0xFF3E312A);

/// 어두운 배너인가.
///
/// 0.45 rather than the usual 0.5: this text is bold and fairly large, and
/// the dark brown holds up a little past the midpoint where white starts to
/// glare.
///
/// 판정이 한곳에 있어야 한다. 글자는 뒤집혔는데 그 옆 표식은 안 뒤집히는
/// 일이 생기면, 두 곳이 서로 다른 기준을 들고 있다는 뜻이다.
bool isDarkBanner(LinearGradient? gradient) {
  if (gradient == null || gradient.colors.isEmpty) return false;
  var sum = 0.0;
  for (final c in gradient.colors) {
    sum += c.computeLuminance();
  }
  return sum / gradient.colors.length <= 0.45;
}

Color profileBannerInk(LinearGradient? gradient, Color? override) {
  if (override != null) return override;
  return isDarkBanner(gradient) ? Colors.white : bannerInkDark;
}

/// 뜻이 있는 색을 배너 위에 얹을 때.
///
/// 준비 완료의 초록, 순위 숫자의 보라처럼 "읽히기만 하면 되는" 색이 아닌
/// 것들이 있다. 그런 색까지 [profileBannerInk] 로 넘기면 밝은 배너에서도
/// 갈색이 되어 뜻을 잃는다 — 배너를 쓴 사람만 준비 표시가 초록이 아니게
/// 된다.
///
/// 그래서 밝은 배너에서는 [light] 를 그대로 두고, 어두운 배너에서만
/// 바꾼다. [override] 는 관리자가 그 배너에 지정한 색이고, 있으면 그것이
/// 답이다 — 누군가 그 배너를 보고 정한 값이다.
Color onBannerAccent(
  LinearGradient? gradient,
  Color? override, {
  required Color light,
}) {
  if (override != null) return override;
  return isDarkBanner(gradient) ? Colors.white : light;
}
