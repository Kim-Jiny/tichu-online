import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class DeviceInfoService {
  /// 기기의 UTC 오프셋(분).
  ///
  /// 저녁 7시에 출석 알림을 보내려면 누구의 7시인지 서버가 알아야 하는데,
  /// 서버는 UTC 한 곳에서 돌고 사용자는 전 세계에 있다. 시가 아니라 분으로
  /// 보내는 이유는 인도(+330)·네팔(+345)처럼 시 단위가 아닌 시간대가 있어서다.
  ///
  /// 문자열인 것은 deviceInfo 가 통째로 `Map<String, String?>` 이기 때문이다.
  /// 서버에서 숫자로 되돌린다.
  static String tzOffsetMinutes() =>
      DateTime.now().timeZoneOffset.inMinutes.toString();

  static Future<Map<String, String?>> collectDeviceInfo({bool includeFcmToken = true, String? locale}) async {
    String? fcmToken;
    String? devicePlatform;
    String? deviceModel;
    String? osVersion;
    String? appVersion;

    // Everything below except the app version is mobile-only; on web the
    // `Platform` reads throw and the catches would leave devicePlatform null,
    // which the server stores as an unknown client. Say 'web' instead.
    //
    // appVersion still resolves on web (PackageInfo reads version.json), and it
    // has to: the server treats a missing version as 0.0.0 and gates every
    // feature past base Tichu on it (server.js:555).
    if (kIsWeb) {
      String? webAppVersion;
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        webAppVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
      } catch (_) {}
      return {
        'fcmToken': null,
        'devicePlatform': 'web',
        'deviceModel': null,
        'osVersion': null,
        'appVersion': webAppVersion,
        'locale': locale,
        'tzOffsetMinutes': tzOffsetMinutes(),
      };
    }

    // FCM Token
    try {
      if (includeFcmToken) {
        // iOS needs APNs token before FCM token can be generated
        if (Platform.isIOS) {
          String? apnsToken;
          for (int i = 0; i < 20; i++) {
            apnsToken = await FirebaseMessaging.instance.getAPNSToken();
            debugPrint('[FCM][DeviceInfo] APNs attempt $i: ${apnsToken != null ? "OK" : "null"}');
            if (apnsToken != null) break;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        fcmToken = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 10));
        final preview = fcmToken != null
            ? fcmToken.substring(0, fcmToken.length.clamp(0, 20))
            : 'null';
        debugPrint('[FCM][DeviceInfo] getToken result: $preview...');
      }
    } catch (e) {
      debugPrint('[FCM][DeviceInfo] Failed to collect token: $e');
    }

    // Platform
    try {
      devicePlatform = Platform.isIOS ? 'ios' : 'android';
    } catch (_) {}

    // Device model & OS version
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceModel = iosInfo.utsname.machine;
        osVersion = iosInfo.systemVersion;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceModel = androidInfo.model;
        osVersion = androidInfo.version.release;
      }
    } catch (_) {}

    // App version
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (_) {}

    return {
      'fcmToken': fcmToken,
      'devicePlatform': devicePlatform,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
      'appVersion': appVersion,
      'locale': locale,
      'tzOffsetMinutes': tzOffsetMinutes(),
    };
  }
}
