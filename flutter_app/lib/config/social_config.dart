import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../firebase_options.dart';

/// Which social providers this particular build can actually sign in with.
///
/// The login screen used to show Google and Kakao unconditionally. On the web
/// that was a lie: Firebase and the Kakao SDK are only initialised when their
/// keys are present, so pressing either button threw and nothing happened —
/// worse than not offering it. Every entry point asks here first.
class SocialConfig {
  SocialConfig._();

  /// Kakao's JavaScript key. Separate from the native key already in main():
  /// Kakao issues one key per platform and rejects the wrong one.
  ///
  ///   flutter build web --dart-define=KAKAO_JS_KEY=...
  ///
  /// Register the serving origin under 카카오 개발자 → 앱 설정 → 플랫폼 → Web.
  /// That domain is what authorises this key — there is no redirect URI to
  /// set: on the web the SDK passes the sentinel 'JS-SDK' instead of a URL
  /// (kakao_flutter_sdk_user/user_api.dart) and Kakao's JS popup flow returns
  /// to the opener rather than navigating anywhere.
  ///
  /// Committed as a default: like the Firebase web keys this is public by
  /// nature — it ships inside the page. What restricts it is the site domain
  /// registered under 플랫폼 → Web.
  static const String kakaoJavaScriptKey = String.fromEnvironment(
    'KAKAO_JS_KEY',
    defaultValue: 'fc15a482c29541d51d894a827bce4bc2',
  );

  static const String kakaoNativeKey = 'd9b4b3cfc86537fed9a80a659641ad30';

  /// Google and Apple both go through Firebase Auth, so on the web they stand
  /// or fall together with the Firebase web config.
  static bool get googleEnabled =>
      kIsWeb ? DefaultFirebaseOptions.hasWebConfig : true;

  /// Native Apple sign-in is iOS-only (it needs the system sheet). On the web
  /// it is an OAuth popup like any other provider, so it works anywhere the
  /// Firebase config is present — Android browsers included.
  static bool get appleEnabled =>
      kIsWeb ? DefaultFirebaseOptions.hasWebConfig : Platform.isIOS;

  static bool get kakaoEnabled =>
      kIsWeb ? kakaoJavaScriptKey.isNotEmpty : true;

  /// True when the "간편 로그인" divider has anything to sit above.
  static bool get anyEnabled => googleEnabled || appleEnabled || kakaoEnabled;
}
