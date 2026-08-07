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

  /// Both hosts, deliberately.
  ///
  /// New links are minted on tichu.kr (server INVITE_BASE_URL), but a player
  /// still on an older build shares tichu.jiny.shop links — and this build has
  /// to open those too. Dropping the old host would break invites between
  /// versions, which is exactly the window a migration creates.
  /// Remove tichu.jiny.shop only when it is retired for good.
  static const Set<String> inviteHosts = {'tichu.kr', 'tichu.jiny.shop'};
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

    if (kIsWeb) {
      // On the web the "link" is just the address bar. /invite?t=… renders a
      // server page (so a shared link still previews with the room name) and
      // then sends the browser here with the token attached — reaching that
      // page at all means the app did not intercept the universal link, i.e.
      // it isn't installed, so the browser is where this invite gets played.
      _storeInviteFromWebUrl();
    }

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

  /// Reads the token straight off the current URL.
  ///
  /// Deliberately does NOT go through _matchesInviteUri: that checks host and
  /// path against the production invite URL, which is wrong here twice over —
  /// the page is served from our own origin (whatever it is: localhost, an
  /// IP, a future domain), and the redirect lands on '/', not '/invite'.
  void _storeInviteFromWebUrl() {
    final q = Uri.base.queryParameters;
    final token = q['invite'] ?? q['t'] ?? q['token'] ?? '';
    if (token.isEmpty) return;
    _pendingInvite = PendingInviteLink(token: token, uri: Uri.base);
    debugPrint('[InviteLinkService] Invite token from web URL');
  }

  bool _matchesInviteUri(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!inviteHosts.contains(host)) return false;
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
