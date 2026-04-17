import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'game_service.dart';
import 'session_service.dart';

class PendingInviteLink {
  const PendingInviteLink({required this.token, required this.uri});

  final String token;
  final Uri uri;
}

class InviteLinkService {
  InviteLinkService._();

  static final InviteLinkService instance = InviteLinkService._();

  static const String inviteHost = 'tichu.jiny.shop';
  static const String invitePath = '/invite';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  PendingInviteLink? _pendingInvite;
  bool _initialized = false;
  bool _processing = false;

  PendingInviteLink? get pendingInvite => _pendingInvite;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initialUri = await _appLinks.getInitialLink();
      _storeInvite(initialUri);
    } catch (e) {
      debugPrint('[InviteLinkService] getInitialLink not available: $e');
    }

    try {
      _linkSubscription = _appLinks.uriLinkStream.listen(
        _storeInvite,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[InviteLinkService] Failed to receive link: $error');
        },
      );
    } catch (e) {
      debugPrint('[InviteLinkService] uriLinkStream not available: $e');
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
    _linkSubscription = null;
    _initialized = false;
  }

  bool _matchesInviteUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (host != inviteHost) return false;
    return uri.path == invitePath || uri.path.startsWith('$invitePath/');
  }

  void _storeInvite(Uri? uri) {
    if (uri == null || !_matchesInviteUri(uri)) return;

    final token =
        uri.queryParameters['t'] ?? uri.queryParameters['token'] ?? '';
    if (token.isEmpty) return;

    _pendingInvite = PendingInviteLink(token: token, uri: uri);
    debugPrint('[InviteLinkService] Stored invite link: $uri');
  }

  Future<void> processPendingInvite(
    SessionService session,
    GameService game,
  ) async {
    final pending = _pendingInvite;
    if (_processing || pending == null) return;
    if (session.isRestoring || !game.isLoggedIn || game.hasRoom) return;

    _processing = true;
    _pendingInvite = null;
    try {
      game.joinRoomByInviteToken(pending.token);
    } finally {
      _processing = false;
    }
  }
}
