import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class DeviceInfoService {
  static Future<Map<String, String?>> collectDeviceInfo({bool includeFcmToken = true}) async {
    String? fcmToken;
    String? devicePlatform;
    String? deviceModel;
    String? osVersion;
    String? appVersion;

    // FCM Token
    try {
      if (includeFcmToken) {
        // iOS needs APNs token before FCM token can be generated
        if (Platform.isIOS) {
          String? apnsToken;
          for (int i = 0; i < 10; i++) {
            apnsToken = await FirebaseMessaging.instance.getAPNSToken();
            if (apnsToken != null) break;
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        fcmToken = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {}

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
    };
  }
}
