import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
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
    iosClientId: '503039725107-tqgloi94e5dnkp18tc2lue5a3u87d7kl.apps.googleusercontent.com',
  );
}
