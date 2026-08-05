import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Thin wrapper around FirebaseAnalytics so callers don't depend on the SDK
/// directly. All methods swallow errors — analytics should never crash the
/// app or block gameplay.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  /// Null on web: main() does not call Firebase.initializeApp there (no web app
  /// is registered yet), and merely touching FirebaseAnalytics.instance throws
  /// from FirebaseCoreWeb.app. A field initialiser makes that a constructor
  /// crash for whoever holds this singleton, which is how it took GameService —
  /// and the whole first frame — down with it.
  final FirebaseAnalytics? _analytics = kIsWeb ? null : FirebaseAnalytics.instance;

  FirebaseAnalyticsObserver? get observer {
    final analytics = _analytics;
    return analytics == null
        ? null
        : FirebaseAnalyticsObserver(analytics: analytics);
  }

  Future<void> setUserId(String? id) async {
    try {
      await _analytics?.setUserId(id: id);
    } catch (_) {}
  }

  Future<void> setUserProperty(String name, String? value) async {
    try {
      await _analytics?.setUserProperty(name: name, value: value);
    } catch (_) {}
  }

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    try {
      await _analytics?.logEvent(name: name, parameters: params);
    } catch (_) {}
  }

  /// Standard `login` event. `method` examples: google, apple, kakao, local.
  Future<void> logLogin(String method) async {
    try {
      await _analytics?.logLogin(loginMethod: method);
    } catch (_) {}
  }

  Future<void> logRoomCreate({
    required String gameType,
    required bool isRanked,
    required int maxPlayers,
  }) =>
      _log('room_create', {
        'game_type': gameType,
        'is_ranked': isRanked ? 1 : 0,
        'max_players': maxPlayers,
      });

  Future<void> logRoomJoin({
    required String gameType,
    required bool isRanked,
  }) =>
      _log('room_join', {
        'game_type': gameType,
        'is_ranked': isRanked ? 1 : 0,
      });

  Future<void> logGameStart({
    required String gameType,
    required bool isRanked,
    required int playerCount,
  }) =>
      _log('game_start', {
        'game_type': gameType,
        'is_ranked': isRanked ? 1 : 0,
        'player_count': playerCount,
      });

  Future<void> logGameEnd({
    required String gameType,
    required bool isRanked,
    bool? won,
  }) =>
      _log('game_end', {
        'game_type': gameType,
        'is_ranked': isRanked ? 1 : 0,
        if (won != null) 'won': won ? 1 : 0,
      });
}
