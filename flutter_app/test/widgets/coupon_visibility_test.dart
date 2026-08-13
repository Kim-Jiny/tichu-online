import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/coupon_redeem.dart';

/// Where the redeem entry points are allowed to appear.
///
/// The iOS app hides them because App Review can read "type a code, receive
/// gold" as a purchase flow. The code itself is printed everywhere; only the
/// ways to redeem are gated. That rule is one boolean, and one boolean written
/// the wrong way round ships a redeem field to the exact platform that must
/// not have one — so it gets a test rather than a comment.
///
/// iOS Safari is the case worth being careful about: it reports
/// TargetPlatform.iOS *and* kIsWeb, and it must keep working.

void main() {
  final original = debugDefaultTargetPlatformOverride;

  tearDown(() {
    debugDefaultTargetPlatformOverride = original;
  });

  test('the iOS app offers no way to redeem', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // In a widget test kIsWeb is false, so this is the installed-app case.
    expect(couponRedeemAllowed, isFalse);
  });

  test('the Android app does', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(couponRedeemAllowed, isTrue);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test('$platform shows them', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(couponRedeemAllowed, isTrue);
    });
  }

  // The Safari-on-iPhone case cannot be asserted here: kIsWeb is a compile
  // time constant and a widget test always runs with it false. It is covered
  // by the shape of the expression — kIsWeb is the first operand, so a web
  // build short-circuits to visible before the platform is even consulted.
}
