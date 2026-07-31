import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import 'player_profile_body.dart';
import 'player_profile_header.dart';

/// Opens the profile popup for [nickname].
///
/// The one popup every screen uses — lobby, the four game screens, the
/// spectator screen, friends and ranking. Each of those used to carry its own
/// copy of this dialog, identical apart from a subtitle and which game's
/// records open first, so a change to the popup had to be made six times and
/// usually wasn't.
///
/// [initialGame] picks which game's records open first — the screen you looked
/// someone up from. [dismissWhen] closes the popup while it is open (the game
/// screens use it to get out of the way when the round ends). [isBot] shows the
/// bot blurb instead of a profile nobody has.
void showPlayerProfileDialog(
  BuildContext context,
  String nickname,
  GameService game, {
  String? initialGame,
  String? subtitle,
  bool isBot = false,
  double maxHeight = 560,
  bool Function(GameService game)? dismissWhen,
  Color placeholderBackground = const Color(0xFFE8F0F7),
  Color placeholderForeground = const Color(0xFF4F6B7A),
}) {
  // A bot has no account, so the fetch would only ever come back empty and the
  // popup would render its "profile not found" error.
  if (!isBot) game.requestProfile(nickname);
  final l10n = L10n.of(context);

  showDialog(
    context: context,
    builder: (ctx) {
      return Consumer<GameService>(
        builder: (ctx, game, _) {
          if (dismissWhen?.call(game) == true) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!ctx.mounted) return;
              final route = ModalRoute.of(ctx);
              if (route != null && route.isCurrent) Navigator.of(ctx).pop();
            });
          }
          final profile = game.profileFor(nickname);
          // Someone else's profile may still be in the store from a previous
          // look-up; wait for this one rather than showing theirs.
          final isLoading =
              !isBot && (profile == null || profile['nickname'] != nickname);

          return AlertDialog(
            // Narrower inset than Material's default 40: at 40 a phone leaves
            // about 216dp of usable width, which is not enough for the three
            // action buttons to sit on one line.
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            actionsPadding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
            // The header sits on the dialog itself. It used to be a bordered
            // card inside the dialog — a frame drawn inside a frame, costing
            // 28dp of width for no information.
            title: PlayerProfileHeader(
              nickname: nickname,
              profile: profile,
              game: game,
              subtitle: subtitle ?? l10n.lobbyPlayerProfile,
              subtitleBuilder: (inner) => profileLevelStrip(
                (inner?['level'] as int?) ?? 1,
                (inner?['expTotal'] as int?) ?? 0,
              ),
              isBot: isBot,
              onCloseDialog: () => Navigator.pop(ctx),
              placeholderBackground: placeholderBackground,
              placeholderForeground: placeholderForeground,
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Replaces the card outline: the header and the records
                  // still need to read as two things.
                  Container(height: 1, color: const Color(0xFFEFE6E1)),
                  const SizedBox(height: 10),
                  if (isBot)
                    SizedBox(width: 300, child: botProfileBody(ctx))
                  else if (isLoading)
                    const SizedBox(
                      height: 140,
                      width: 320,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    Flexible(
                      child: SingleChildScrollView(
                        child: PlayerProfileBody(
                          data: profile!,
                          game: game,
                          initialGame: initialGame ?? game.currentGameType,
                        ),
                      ),
                    ),
                ],
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
