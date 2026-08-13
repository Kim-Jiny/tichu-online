import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/utils/banner_ink.dart';

/// Which colour the profile popup writes a nickname in once someone's banner
/// is behind it.
///
/// Banners are admin-editable and range from pastel to near-black, so the one
/// thing that must never happen is a nickname the same brightness as the fill
/// it sits on. Most of the shipped banners carry no explicit text colour, which
/// is exactly the case a fixed dark brown got wrong.

void main() {
  LinearGradient g(List<Color> colors) => LinearGradient(colors: colors);

  const dark = Color(0xFF3E312A);

  test('an explicit text colour is the answer, whatever the fill', () {
    // Someone looked at this banner and chose. Even a choice that contradicts
    // the luminance rule stands — the rule is only a fallback.
    expect(
      profileBannerInk(g([Colors.white, Colors.white]), Colors.pink),
      Colors.pink,
    );
  });

  test('a dark banner gets white', () {
    expect(
      profileBannerInk(g([const Color(0xFF0D1B3E), const Color(0xFF1A1035)]), null),
      Colors.white,
    );
  });

  test('a pastel banner keeps the popup brown', () {
    expect(
      profileBannerInk(g([const Color(0xFFF6C1C9), const Color(0xFFF3E7EA)]), null),
      dark,
    );
  });

  test('a banner that runs dark to light is judged on the whole run', () {
    // The header spans the entire gradient, so neither end alone decides. Black
    // to mid-grey averages dark; white to mid-grey averages light. Sampling one
    // end would give the same answer for both.
    expect(
      profileBannerInk(g([Colors.black, const Color(0xFF555555)]), null),
      Colors.white,
    );
    expect(
      profileBannerInk(g([Colors.white, const Color(0xFFBBBBBB)]), null),
      dark,
    );
  });

  test('no banner means the plain popup', () {
    expect(profileBannerInk(null, null), dark);
    // A gradient with no stops is what a malformed catalog entry parses to.
    expect(profileBannerInk(g(const []), null), dark);
  });
}
