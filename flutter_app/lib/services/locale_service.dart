import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Supported locales for the app.
const supportedLocales = [
  Locale('en'),
  Locale('ko'),
  Locale('de'),
];

/// Manages the user's locale preference.
///
/// - `userSelectedLocale == null` → follow device language (fallback to English).
/// - Otherwise → use the exact locale the user picked in Settings.
class LocaleService extends ChangeNotifier {
  static const _prefsKey = 'user_selected_locale';

  Locale? _userSelectedLocale;

  /// The locale the user explicitly chose, or null for "Auto (system)".
  Locale? get userSelectedLocale => _userSelectedLocale;

  /// The locale the app should actually render in.
  Locale get effectiveLocale {
    if (_userSelectedLocale != null) return _userSelectedLocale!;
    return _resolveDeviceLocale();
  }

  /// Resolve the device locale to the closest supported locale (fallback en).
  Locale _resolveDeviceLocale() {
    final deviceLocale = PlatformDispatcher.instance.locale;
    for (final supported in supportedLocales) {
      if (supported.languageCode == deviceLocale.languageCode) {
        return supported;
      }
    }
    return const Locale('en'); // fallback
  }

  /// Load the saved preference from SharedPreferences.
  Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null) {
      final match = supportedLocales.where((l) => l.languageCode == code);
      _userSelectedLocale = match.isNotEmpty ? match.first : null;
    }
    notifyListeners();
  }

  /// Set the user's locale preference. Pass null for "Auto (system)".
  Future<void> setLocale(Locale? locale) async {
    _userSelectedLocale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, locale.languageCode);
    }
  }
}
