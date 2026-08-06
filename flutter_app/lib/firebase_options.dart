import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // A Web app is a separate registration in the Firebase console, with its own
  // apiKey and appId — they cannot be derived from the Android/iOS ones below.
  // Passed at build time so the repo does not have to be edited to turn web
  // sign-in on:
  //
  //   flutter build web --dart-define=FIREBASE_WEB_API_KEY=... \
  //                     --dart-define=FIREBASE_WEB_APP_ID=...
  //
  // These are not secrets — a web app ships them in plain sight, and Firebase
  // says so. What actually protects the project is the authorised-domains list
  // in Authentication → Settings. Keep tichu.jiny.shop on it.
  //
  // Committed as defaults so a plain `flutter build web` works; the
  // --dart-define still wins if you ever need to point a build at another
  // Firebase project without editing this file.
  static const String _webApiKey = String.fromEnvironment(
    'FIREBASE_WEB_API_KEY',
    defaultValue: '',
  );
  static const String _webAppId = String.fromEnvironment(
    'FIREBASE_WEB_APP_ID',
    defaultValue: '1:503039725107:web:0336b42005b7f629571d46',
  );

  /// Whether this build can talk to Firebase at all on the web.
  ///
  /// Everything web-side that needs Firebase (Google and Apple sign-in) is
  /// gated on this, so a build without the keys degrades to id/password
  /// instead of throwing on boot or, worse, showing buttons that do nothing.
  static bool get hasWebConfig => _webApiKey.isNotEmpty && _webAppId.isNotEmpty;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: _webApiKey,
    appId: _webAppId,
    // Shared across the whole project, so these are the same as Android/iOS.
    messagingSenderId: '503039725107',
    projectId: 'tichu-online-95',
    // The domain Firebase hosts the OAuth handler on. Sign-in popups land here
    // before bouncing back, which is why it must be present on web.
    authDomain: 'tichu-online-95.firebaseapp.com',
    storageBucket: 'tichu-online-95.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB76qN7hKNCbVfZfdmqtQN5ZH6vwwWlQGg',
    appId: '1:503039725107:android:563e774d177ee992571d46',
    messagingSenderId: '503039725107',
    projectId: 'tichu-online-95',
    storageBucket: 'tichu-online-95.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCB4EYrUclvR48a53G3dYrSvtmgyPXCX7I',
    appId: '1:503039725107:ios:434de51d37fc3187571d46',
    messagingSenderId: '503039725107',
    projectId: 'tichu-online-95',
    storageBucket: 'tichu-online-95.firebasestorage.app',
    iosBundleId: 'com.jiny.tichuOnline',
    iosClientId:
        '503039725107-tqgloi94e5dnkp18tc2lue5a3u87d7kl.apps.googleusercontent.com',
  );
}
