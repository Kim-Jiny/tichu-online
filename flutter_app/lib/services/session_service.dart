import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'device_info_service.dart';
import 'game_service.dart';
import 'network_service.dart';

enum SessionAuthStatus { success, needsNickname, failed, cancelled }

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

class SessionService {
  SessionService(this._network, this._game);

  final NetworkService _network;
  final GameService _game;

  bool _restoreInProgress = false;

  Future<void> ensureConnected([String? url]) async {
    if (_network.isConnected || _network.isConnecting) return;
    await _network.connect(url);
  }

  Future<SessionAuthResult> loginWithCredentials(
    String username,
    String password, {
    String? url,
    bool persistCredentials = true,
  }) async {
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
    _restoreInProgress = true;
    try {
      final savedProvider = await AuthService.getSavedProvider();
      if (savedProvider != null) {
        final token = await AuthService.refreshToken(savedProvider);
        if (token != null && token.isNotEmpty) {
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
            return false;
          }
        } else {
          await AuthService.clearAuthInfo();
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('saved_username');
      final password = prefs.getString('saved_password');
      if (username != null && password != null && username.isNotEmpty) {
        final result = await loginWithCredentials(
          username,
          password,
          persistCredentials: true,
        );
        if (result.status == SessionAuthStatus.success) {
          await _refreshPostLoginData();
          return true;
        }
      }

      return false;
    } finally {
      _restoreInProgress = false;
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
    await clearPersistedSession();
    await AuthService.signOut();
  }

  Future<void> clearPersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_username');
    await prefs.remove('saved_password');
    await AuthService.clearAuthInfo();
  }

  void _prepareForLogin() {
    _game.playerId = '';
    _game.loginError = null;
    _game.needNickname = false;
    _game.gameState = null;
    _game.spectatorGameState = null;
  }

  Future<Map<String, String?>?> _collectDeviceInfo() async {
    try {
      return await DeviceInfoService.collectDeviceInfo();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _waitForLoginResult() async {
    if (_game.playerId.isNotEmpty) return true;
    if (_game.loginError != null) return false;

    final completer = Completer<bool>();

    void listener() {
      if (_game.playerId.isNotEmpty) {
        if (!completer.isCompleted) completer.complete(true);
      } else if (_game.loginError != null) {
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
      if (_game.playerId.isNotEmpty) {
        if (!completer.isCompleted) {
          completer.complete(const SessionAuthResult.success());
        }
      } else if (_game.needNickname) {
        if (!completer.isCompleted) {
          completer.complete(const SessionAuthResult.needsNickname());
        }
      } else if (_game.loginError != null) {
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
      return const SessionAuthResult.failed('서버 응답 시간 초과');
    } finally {
      _game.removeListener(listener);
    }
  }

  Future<void> _refreshPostLoginData() async {
    if (_game.currentRoomId.isNotEmpty) {
      _game.checkRoom();
    }

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
}
