import 'package:flutter/material.dart';
import '../theme/cartoon.dart';

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
///
/// 팔레트를 거치지 않는다. 배너는 산 물건이라 어느 한 벌에서나 제 색
/// 그대로이고, 이 값은 [isDarkBanner] 가 거짓일 때 — 즉 밝은 배너
/// 위에서만 쓰인다. 변환을 태우면 어두운 한 벌에서 밝아져, 밝은 배너에
/// 밝은 글자가 올라간다.
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

/// 배너를 쓴 프로필 팝업에서, 기록이 얹히는 판의 색.
///
/// 흰색으로 박아두면 배너가 머리글과 테두리로만 남는다 — 팝업 가운데를
/// 다 차지하는 판이 흰색이니, 그 사람 배너를 보여주려던 뜻이 거의
/// 사라진다. 어두운 한 벌에서는 더 나쁘다: 판은 흰데 그 위의 글자는
/// 팔레트 잉크(밝은 크림)라 아무것도 읽히지 않는다.
///
/// 그래서 판은 팔레트의 종이색에서 출발해 배너 쪽으로 조금 당긴다.
/// 밝은 한 벌에서는 흰 판에 그 배너의 기운이 돌고, 어두운 한 벌에서는
/// 어두운 판이 되어 팔레트 잉크가 그대로 읽힌다. 어느 쪽이든 판의
/// 밝기는 팔레트가 정하고, 색조만 배너가 정한다.
///
/// 0.14 만 당긴다. 배너가 어느 배너인지 보일 만큼은 되어야 하고, 판
/// 위에 얹힌 승패색·등급색의 뜻을 흐릴 만큼은 안 되어야 한다.
Color bannerSheet(LinearGradient gradient) {
  if (gradient.colors.isEmpty) return Cartoon.paper;
  var r = 0.0;
  var g = 0.0;
  var b = 0.0;
  for (final c in gradient.colors) {
    r += c.r;
    g += c.g;
    b += c.b;
  }
  final n = gradient.colors.length;
  final average = Color.from(alpha: 1, red: r / n, green: g / n, blue: b / n);
  return Color.lerp(Cartoon.paper, average, 0.14)!;
}
