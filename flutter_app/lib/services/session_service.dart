import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_navigation.dart';
import 'auth_service.dart';
import 'device_info_service.dart';
import 'game_service.dart';
import 'network_service.dart';

enum SessionAuthStatus { success, needsNickname, failed, cancelled }
enum RestorePhase {
  idle,
  refreshingSocialToken,
  restoringSocialSession,
  restoringLocalSession,
  restoringRoomState,
  loadingLobbyData,
  failed,
}

class SessionAuthResult {
  final SessionAuthStatus status;
  final String? error;

  const SessionAuthResult._(this.status, [this.error]);

  const SessionAuthResult.success() : this._(SessionAuthStatus.success);
  const SessionAuthResult.needsNickname() : this._(SessionAuthStatus.needsNickname);
  const SessionAuthResult.cancelled() : this._(SessionAuthStatus.cancelled);
  const SessionAuthResult.failed([String? error])
      : this._(SessionAuthStatus.failed, error);
}

class SessionService extends ChangeNotifier {
  SessionService(this._network, this._game);

  final NetworkService _network;
  final GameService _game;

  bool _restoreInProgress = false;
  bool _skipNextAutoRestore = false;
  RestorePhase _restorePhase = RestorePhase.idle;
  String? _restoreError;

  bool get isRestoring => _restoreInProgress;
  RestorePhase get restorePhase => _restorePhase;
  String? get restoreError => _restoreError;
  bool get hasRestoreError => _restoreError != null;
  /// Returns the raw restore error string (may be a server message or a key).
  /// Widgets should prefer mapping [restorePhase] via l10n.
  String? get restoreErrorRaw => _restoreError;

  bool consumeAutoRestoreSuppression() {
    if (!_skipNextAutoRestore) return false;
    _skipNextAutoRestore = false;
    return true;
  }

  void clearAutoRestoreSuppression() {
    _skipNextAutoRestore = false;
  }

  void clearRestoreFeedback() {
    if (_restoreInProgress) {
      if (_restoreError == null) return;
      _restoreError = null;
      notifyListeners();
      return;
    }
    if (_restorePhase == RestorePhase.idle && _restoreError == null) return;
    _restorePhase = RestorePhase.idle;
    _restoreError = null;
    notifyListeners();
  }

  Future<void> ensureConnected([String? url]) async {
    await _network.ensureConnected(url);
  }

  Future<SessionAuthResult> loginWithCredentials(
    String username,
    String password, {
    String? url,
    bool persistCredentials = true,
  }) async {
    clearAutoRestoreSuppression();
    clearRestoreFeedback();
    await ensureConnected(url);
    final deviceInfo = await _collectDeviceInfo();
    _prepareForLogin();
    _game.loginWithCredentials(username, password, deviceInfo: deviceInfo);

    final loggedIn = await _waitForLoginResult();
    if (!loggedIn) {
      return SessionAuthResult.failed(_game.loginError);
    }

    if (persistCredentials) {
      await _saveCredentials(username, password);
    }
    await AuthService.clearAuthInfo();
    return const SessionAuthResult.success();
  }

  Future<SessionAuthResult> loginWithSocial(
    String provider,
    String token, {
    String? url,
    bool persistProvider = true,
  }) async {
    clearAutoRestoreSuppression();
    clearRestoreFeedback();
    await ensureConnected(url);
    final deviceInfo = await _collectDeviceInfo();
    _prepareForLogin();
    _game.loginSocial(provider, token, deviceInfo: deviceInfo);

    return _waitForSocialLoginResult(provider, persistProvider: persistProvider);
  }

  Future<SessionAuthResult> completeSocialRegistration(
    String provider,
    String token,
    String nickname, {
    bool existingUser = false,
  }) async {
    clearAutoRestoreSuppression();
    clearRestoreFeedback();
    final deviceInfo = await _collectDeviceInfo();
    _prepareForLogin();
    _game.registerSocial(
      provider,
      token,
      nickname,
      existingUser: existingUser,
      deviceInfo: deviceInfo,
    );

    final loggedIn = await _waitForLoginResult();
    if (!loggedIn) {
      return SessionAuthResult.failed(_game.loginError);
    }

    await AuthService.saveAuthInfo(provider);
    return const SessionAuthResult.success();
  }

  Future<bool> restoreSavedSession() async {
    if (_restoreInProgress) return false;
    _setRestoring(true);
    _restoreError = null;
    try {
      final savedProvider = await AuthService.getSavedProvider();
      if (savedProvider != null) {
        _setRestorePhase(RestorePhase.refreshingSocialToken);
        final token = await AuthService.refreshToken(savedProvider);
        if (token != null && token.isNotEmpty) {
          _setRestorePhase(RestorePhase.restoringSocialSession);
          final result = await loginWithSocial(
            savedProvider,
            token,
            persistProvider: true,
          );
          if (result.status == SessionAuthStatus.success) {
            await _refreshPostLoginData();
            return true;
          }
          if (result.status == SessionAuthStatus.needsNickname) {
            _setRestoreFailure('needs_nickname');
            return false;
          }
          _restoreError = result.error ?? 'social_restore_failed';
        } else {
          _restoreError = 'social_token_expired';
        }
        _setRestoreFailure(_restoreError ?? 'social_restore_failed');
        return false;
      }

      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('saved_username');
      final password = prefs.getString('saved_password');
      if (username != null && password != null && username.isNotEmpty) {
        _setRestorePhase(RestorePhase.restoringLocalSession);
        final result = await loginWithCredentials(
          username,
          password,
          persistCredentials: true,
        );
        if (result.status == SessionAuthStatus.success) {
          await _refreshPostLoginData();
          return true;
        }
        _restoreError = result.error ?? 'local_restore_failed';
        _setRestoreFailure(_restoreError!);
        return false;
      }

      // No saved credentials at all — not an error, just nothing to restore
      return false;
    } catch (_) {
      _setRestoreFailure(_restoreError ?? 'auto_restore_error');
      return false;
    } finally {
      _setRestoring(false);
    }
  }

  Future<bool> reconnectAndRestore() async {
    final success = await _network.reconnect();
    if (!success) return false;
    return restoreSavedSession();
  }

  Future<void> logout() async {
    _network.disconnect(intentional: true);
    _game.reset();
    _skipNextAutoRestore = true;
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    await clearPersistedSession();
    await AuthService.signOut();
  }

  void resetToLoginState({bool suppressAutoRestore = false}) {
    _network.disconnect(intentional: true);
    _game.reset();
    appNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    if (suppressAutoRestore) {
      _skipNextAutoRestore = true;
    }
  }

  Future<void> clearPersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
    await AuthService.clearAuthInfo();
  }

  void _prepareForLogin() {
    _game.prepareForLoginAttempt();
  }

  Future<Map<String, String?>?> _collectDeviceInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLocale = prefs.getString('user_selected_locale');
      final locale = savedLocale ?? PlatformDispatcher.instance.locale.languageCode;
      return await DeviceInfoService.collectDeviceInfo(includeFcmToken: false, locale: locale);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _waitForLoginResult() async {
    if (_game.isLoggedIn) return true;
    if (_game.hasLoginError) return false;

    final completer = Completer<bool>();

    void listener() {
      if (_game.isLoggedIn) {
        if (!completer.isCompleted) completer.complete(true);
      } else if (_game.hasLoginError) {
        if (!completer.isCompleted) completer.complete(false);
      }
    }

    _game.addListener(listener);
    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      return false;
    } finally {
      _game.removeListener(listener);
    }
  }

  Future<SessionAuthResult> _waitForSocialLoginResult(
    String provider, {
    required bool persistProvider,
  }) async {
    final completer = Completer<SessionAuthResult>();

    void listener() {
      if (_game.isLoggedIn) {
        if (!completer.isCompleted) {
          completer.complete(const SessionAuthResult.success());
        }
      } else if (_game.hasPendingSocialNickname) {
        if (!completer.isCompleted) {
          completer.complete(const SessionAuthResult.needsNickname());
        }
      } else if (_game.hasLoginError) {
        if (!completer.isCompleted) {
          completer.complete(SessionAuthResult.failed(_game.loginError));
        }
      }
    }

    _game.addListener(listener);
    try {
      final result = await completer.future.timeout(const Duration(seconds: 15));
      if (result.status == SessionAuthStatus.success && persistProvider) {
        await AuthService.saveAuthInfo(provider);
      }
      return result;
    } catch (_) {
      return const SessionAuthResult.failed('server_timeout');
    } finally {
      _game.removeListener(listener);
    }
  }

  Future<void> _refreshPostLoginData() async {
    _setRestorePhase(RestorePhase.restoringRoomState);
    var restored = false;
    const restoreTimeouts = <Duration>[
      Duration(seconds: 8),
      Duration(seconds: 8),
      Duration(seconds: 5),
    ];
    for (final timeout in restoreTimeouts) {
      restored = await _game.checkRoomAndWait(timeout: timeout);
      if (restored || !_network.isConnected) {
        break;
      }
    }
    if (!restored) {
      _game.fallbackToLobbyAfterRestoreFailure();
    }

    _setRestorePhase(RestorePhase.loadingLobbyData);
    _game.requestRoomList();
    _game.requestSpectatableRooms();
    _game.requestBlockedUsers();
    _game.requestFriends();
    _game.requestPendingFriendRequests();
    _game.requestDmConversations();
    _game.requestUnreadDmCount();

    if (_game.roomList.isEmpty) {
      final roomCompleter = Completer<void>();
      void roomListener() {
        if (roomCompleter.isCompleted) return;
        if (_game.roomList.isNotEmpty) {
          roomCompleter.complete();
        }
      }

      _game.addListener(roomListener);
      try {
        await roomCompleter.future.timeout(const Duration(seconds: 2));
      } catch (_) {
      } finally {
        _game.removeListener(roomListener);
      }
    }
  }

  Future<void> _saveCredentials(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_username', username);
    await prefs.setString('saved_password', password);
  }

  void _setRestoring(bool value) {
    if (_restoreInProgress == value) return;
    _restoreInProgress = value;
    if (!value && _restorePhase != RestorePhase.failed) {
      _restorePhase = RestorePhase.idle;
    }
    notifyListeners();
  }

  void _setRestorePhase(RestorePhase phase) {
    if (_restorePhase == phase) return;
    _restorePhase = phase;
    notifyListeners();
  }

  void _setRestoreFailure(String message) {
    _restoreError = message;
    _restorePhase = RestorePhase.failed;
    notifyListeners();
  }
}
