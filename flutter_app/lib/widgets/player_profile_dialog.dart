import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import 'player_profile_body.dart';
import 'player_profile_header.dart';

/// Opens the profile popup for [nickname].
///
/// The header and body were already shared widgets; this is the dialog around
/// them, which each screen had been repeating. New callers should use this
/// rather than copying the wrapper a seventh time.
///
/// [initialGame] picks which game's records open first — the screen you looked
/// someone up from.
void showPlayerProfileDialog(
  BuildContext context,
  String nickname,
  GameService game, {
  String? initialGame,
  String? subtitle,
}) {
  game.requestProfile(nickname);
  final l10n = L10n.of(context);

  showDialog(
    context: context,
    builder: (ctx) {
      return Consumer<GameService>(
        builder: (ctx, game, _) {
          final profile = game.profileFor(nickname);
          // Someone else's profile may still be in the store from a previous
          // look-up; wait for this one rather than showing theirs.
          final isLoading = profile == null || profile['nickname'] != nickname;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            contentPadding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            title: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8DDD8)),
              ),
              child: PlayerProfileHeader(
                nickname: nickname,
                profile: profile,
                game: game,
                subtitle: subtitle ?? l10n.lobbyPlayerProfile,
                subtitleBuilder: (inner) => profileLevelStrip(
                  (inner?['level'] as int?) ?? 1,
                  (inner?['expTotal'] as int?) ?? 0,
                ),
                onCloseDialog: () => Navigator.pop(ctx),
              ),
            ),
            content: isLoading
                ? const SizedBox(
                    height: 140,
                    width: 360,
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 420,
                      maxHeight: 560,
                    ),
                    child: SingleChildScrollView(
                      child: PlayerProfileBody(
                        data: profile,
                        game: game,
                        initialGame: initialGame ?? game.currentGameType,
                      ),
                    ),
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10n.commonClose),
              ),
            ],
          );
        },
      );
    },
  );
}
