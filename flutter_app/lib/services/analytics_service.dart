import 'package:firebase_analytics/firebase_analytics.dart';

/// Thin wrapper around FirebaseAnalytics so callers don't depend on the SDK
/// directly. All methods swallow errors — analytics should never crash the
/// app or block gameplay.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;

  FirebaseAnalyticsObserver get observer =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  Future<void> setUserId(String? id) async {
    try {
      await _analytics.setUserId(id: id);
    } catch (_) {}
  }

  Future<void> setUserProperty(String name, String? value) async {
    try {
      await _analytics.setUserProperty(name: name, value: value);
    } catch (_) {}
  }

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (_) {}
  }

  /// Standard `login` event. `method` examples: google, apple, kakao, local.
  Future<void> logLogin(String method) async {
    try {
      await _analytics.logLogin(loginMethod: method);
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
