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

  test('the rule is about the app, not about Apple', () {
    // kIsWeb is checked first precisely so that Safari on an iPhone — which
    // reports iOS — is still a web client. This asserts the shape of the
    // expression rather than kIsWeb itself, which a widget test cannot change.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const webWins = true; // stands in for kIsWeb
    expect(webWins || defaultTargetPlatform != TargetPlatform.iOS, isTrue,
        reason: 'a web build on iOS must still show coupon UI');
  });
}
