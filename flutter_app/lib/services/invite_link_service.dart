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

  /// Custom-scheme fallback: `tichuonline://invite?t=…`.
  ///
  /// App links are the primary path, but some in-app browsers (KakaoTalk,
  /// Instagram) render an https link themselves instead of handing it to the
  /// app. A scheme URL they cannot render gets passed through. Nothing mints
  /// these yet — the registration exists so a future link can use it without
  /// waiting on another store release.
  static const String inviteScheme = 'tichuonline';

  /// KakaoTalk share card button on Android/iOS. The template's app-scheme link is
  /// `<kakao scheme>://kakaolink?type=invite&t=<token>` and the prefix cannot be
  /// changed in the Kakao console, so the app has to accept it as it is.
  /// This is the app's native key scheme (same value as AndroidManifest.xml and
  /// Info.plist) — not a secret.
  static const String kakaoLinkScheme = 'kakaod9b4b3cfc86537fed9a80a659641ad30';

  static bool _matchesInviteUri(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    // In a scheme URL the authority carries what would be the path:
    // tichuonline://invite?t=… parses as host 'invite', path ''.
    if (scheme == inviteScheme) {
      return uri.host.toLowerCase() == 'invite';
    }
    if (scheme == kakaoLinkScheme) {
      // The same scheme is used by Kakao login (host 'oauth'); only the share
      // card's invite button is an invite.
      final type = uri.queryParameters['type'];
      return uri.host.toLowerCase() == 'kakaolink' &&
          (type == null || type == 'invite');
    }
    final host = uri.host.toLowerCase();
    if (!inviteHosts.contains(host)) return false;
    return uri.path == invitePath || uri.path.startsWith('$invitePath/');
  }

  /// The invite token a link carries, or null if it is not an invite link.
  @visibleForTesting
  static String? inviteTokenFromUri(Uri? uri) {
    if (uri == null || !_matchesInviteUri(uri)) return null;
    final token =
        uri.queryParameters['t'] ?? uri.queryParameters['token'] ?? '';
    return token.isEmpty ? null : token;
  }

  void _storeInvite(Uri? uri) {
    final token = inviteTokenFromUri(uri);
    if (token == null) return;

    _pendingInvite = PendingInviteLink(token: token, uri: uri!);
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
