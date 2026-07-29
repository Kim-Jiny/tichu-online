package com.jiny.tichuOnline

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Deep-link into this app's own settings page, so a user who denied the
    // camera can actually get to the switch. url_launcher can do this on iOS
    // (app-settings:) but has no equivalent on Android, and pulling in a
    // permissions plugin for one intent would mean another pod on a project
    // that has already lost time to CocoaPods conflicts.
    private val channel = "com.jiny.tichuOnline/app_settings"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                if (call.method == "openAppSettings") {
                    try {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
