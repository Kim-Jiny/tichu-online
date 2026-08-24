import Flutter
import UIKit
import Firebase
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pushTapChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()

    // Explicitly register for remote notifications
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    print("[iOS][APNs] registerForRemoteNotifications called")

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // The bridge exposes a plugin registry, not a messenger — take one the way
    // any plugin would, through its own registrar.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppSettingsChannel") {
      registerAppSettingsChannel(registrar.messenger())
      pushTapChannel = FlutterMethodChannel(
        name: "com.jiny.tichuOnline/push_tap",
        binaryMessenger: registrar.messenger()
      )
    }
  }

  // Deep-link into this app's own settings page, so a user who denied the
  // camera can actually get to the switch. Paired with the Android side in
  // MainActivity.kt; a hand-rolled channel rather than a permissions plugin,
  // which would mean another pod on a project that has already lost time to
  // CocoaPods conflicts.
  private func registerAppSettingsChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.jiny.tichuOnline/app_settings",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "openAppSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let url = URL(string: UIApplication.openSettingsURLString),
            UIApplication.shared.canOpenURL(url) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { ok in result(ok) }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    print("[iOS][APNs] SUCCESS - token received: \(deviceToken.count) bytes")
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("[iOS][APNs] FAILED - \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  // Owning UNUserNotificationCenter.delegate (above) means we must decide
  // presentation ourselves — without this, iOS defaults to showing nothing
  // while the app is foregrounded, even though the Dart side already asked
  // for alert/badge/sound via setForegroundNotificationPresentationOptions.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound, .badge])
  }

  // FirebaseMessaging's onMessageOpenedApp/getInitialMessage only cover a tap
  // that brings the app from background/killed to foreground — a tap on the
  // banner shown by willPresent above, while the app was already active,
  // reaches neither. Since we already own this delegate, catch that tap here
  // directly and hand the payload to Dart ourselves rather than depend on a
  // Firebase code path that does not fire for it. Runs for every tap (this
  // app was foreground or not), which can double up with onMessageOpenedApp
  // for the background case — recordPushTap on the Dart side is idempotent,
  // so that overlap is harmless.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    var data: [String: String] = [:]
    for (key, value) in response.notification.request.content.userInfo {
      if let k = key as? String, let v = value as? String { data[k] = v }
    }
    if !data.isEmpty { pushTapChannel?.invokeMethod("tap", arguments: data) }
    completionHandler()
  }
}
