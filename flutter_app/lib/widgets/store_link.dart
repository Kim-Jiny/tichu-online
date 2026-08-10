import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sending someone from the web build to the store.
///
/// A few things can only happen in the app. The web build shows them the same
/// way it always did and swaps the action for one of these links, so nobody
/// has to be told a feature exists somewhere else — they can see it and go.

const String kAppStoreUrl =
    'https://apps.apple.com/app/tichu-online/id6759035151';
const String kPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=com.jiny.tichuOnline';

/// The store that matches whatever this browser is running on.
///
/// `defaultTargetPlatform` reads the user agent on the web, so an iPhone in
/// Safari gets the App Store and an Android phone gets Play. On a desktop
/// browser it is neither, and [storeChoicesFor] offers both instead of
/// guessing.
List<({String label, String url})> storeChoicesFor(TargetPlatform platform) {
  const apple = (label: 'App Store', url: kAppStoreUrl);
  const play = (label: 'Google Play', url: kPlayStoreUrl);
  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return [apple];
    case TargetPlatform.android:
      return [play];
    default:
      return [play, apple];
  }
}

Future<void> openStoreUrl(String url) async {
  final uri = Uri.parse(url);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    // Some browsers refuse the external-application mode; the plain call is
    // the one that works there.
    await launchUrl(uri);
  }
}
