import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';

/// Getting someone from the web build into the app.
///
/// Some things only exist in the app — the daily attendance reward is claimed
/// by watching a rewarded ad, and AdMob has no web implementation. Rather than
/// hiding those features on the web and leaving a hole where they should be,
/// show them and offer the store.

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

/// "This one is in the app" — with the way to get it.
///
/// [body] says which feature they reached for, so the dialog explains the
/// thing they just tapped rather than advertising in the abstract.
void showGetTheAppDialog(BuildContext context, {required String body}) {
  final l10n = L10n.of(context);
  final choices = storeChoicesFor(defaultTargetPlatform);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.phone_iphone, size: 20, color: Color(0xFF4A4080)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.getTheAppTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Text(
          body,
          style: const TextStyle(fontSize: 13, height: 1.45),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.commonClose),
        ),
        for (final c in choices)
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openStoreUrl(c.url);
            },
            child: Text(c.label),
          ),
      ],
    ),
  );
}
