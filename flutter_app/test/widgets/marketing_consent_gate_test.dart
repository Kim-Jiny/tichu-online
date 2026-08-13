import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/marketing_push.dart';

/// Which of the two marketing dialogs may open, and where.
///
/// The rule is not symmetric, which is why it gets a test rather than a
/// comment. Asking for consent on the web is pointless — web builds never
/// register an FCM token, so a yes buys the player nothing — and leaving the
/// question unanswered is what makes the app ask properly later. The
/// two-yearly confirmation is the opposite case: it is owed to someone who
/// already said yes, and for a player who has stopped opening the app the web
/// may be the only place left to tell them.
///
/// Getting these backwards is silent both ways: a popup nobody needed on the
/// web funnel, or a legal notice that never reaches anyone.

void main() {
  test('consent is never asked for on the web', () {
    expect(marketingConsentAskAllowed(isWeb: true), isFalse);
  });

  test('but is on an installed app', () {
    expect(marketingConsentAskAllowed(isWeb: false), isTrue);
  });

  test('the two-yearly confirmation shows everywhere, web included', () {
    expect(marketingConfirmNoticeAllowed(isWeb: true), isTrue);
    expect(marketingConfirmNoticeAllowed(isWeb: false), isTrue);
  });

  test('the running build agrees with the constant it is compiled with', () {
    // Guards against the predicate being wired to something other than kIsWeb.
    expect(marketingConsentAskAllowed(isWeb: kIsWeb), !kIsWeb);
  });
}
