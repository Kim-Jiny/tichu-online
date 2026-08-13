import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/coupon_redeem.dart';

/// Where coupon UI is allowed to appear.
///
/// The iOS app hides it because App Review can read "type a code, receive
/// gold" as a purchase flow. That rule is one boolean, and one boolean written
/// the wrong way round ships a coupon field to the exact platform that must
/// not have one — so it gets a test rather than a comment.
///
/// iOS Safari is the case worth being careful about: it reports
/// TargetPlatform.iOS *and* kIsWeb, and it must keep working.

void main() {
  final original = debugDefaultTargetPlatformOverride;

  tearDown(() {
    debugDefaultTargetPlatformOverride = original;
  });

  test('the iOS app shows nothing about coupons', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // In a widget test kIsWeb is false, so this is the installed-app case.
    expect(couponUiVisible, isFalse);
  });

  test('the Android app shows them', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(couponUiVisible, isTrue);
  });

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test('$platform shows them', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(couponUiVisible, isTrue);
    });
  }

  // The Safari-on-iPhone case cannot be asserted here: kIsWeb is a compile
  // time constant and a widget test always runs with it false. It is covered
  // by the shape of the expression — kIsWeb is the first operand, so a web
  // build short-circuits to visible before the platform is even consulted.
}
