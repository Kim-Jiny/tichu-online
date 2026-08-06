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
  /// Also register the serving origin under 카카오 개발자 → 앱 설정 →
  /// 플랫폼 → Web, and the redirect URI under 카카오 로그인.
  static const String kakaoJavaScriptKey = String.fromEnvironment(
    'KAKAO_JS_KEY',
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
