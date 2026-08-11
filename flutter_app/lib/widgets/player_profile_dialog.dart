import 'dart:math' as math;

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
/// someone up from. Left out, the popup opens on the combined record: from the
/// lobby or the friends list there is no game in play, and defaulting to
/// whichever one was last touched showed a Tichu-only record to someone who
/// only came to see how the player is doing. [dismissWhen] closes the popup
/// while it is open (the game screens use it to get out of the way when the
/// round ends). [isBot] shows the bot blurb instead of a profile nobody has.
///
/// [maxHeight] caps the records area. Left null it takes what the screen can
/// spare, which on anything bigger than a small phone is a good deal more than
/// the fixed 560 it used to get.
void showPlayerProfileDialog(
  BuildContext context,
  String nickname,
  GameService game, {
  String? initialGame,
  String? subtitle,
  bool isBot = false,
  double? maxHeight,
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

          // Take the width the screen has instead of letting the dialog shrink
          // to whatever the widest chip happened to be. 32 for the inset and 32
          // for the content padding; 480 is where the stat cards stop gaining
          // anything from more room.
          final media = MediaQuery.of(ctx).size;
          final contentWidth = math.max(
            240.0,
            math.min(media.width - 64, 480.0),
          );
          // Header, actions and inset come off the top before the records get
          // their share.
          final available = (media.height - 190).clamp(220.0, 680.0);
          final contentMaxHeight = maxHeight == null
              ? available
              : math.min(maxHeight, available);

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
              // A private profile sends no level, and the strip's fallback
              // ("Lv.1 0/100") reads as a real level rather than as a blank.
              subtitleBuilder: (inner) => inner?['level'] == null
                  ? Text(
                      subtitle ?? l10n.lobbyPlayerProfile,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF84766E),
                      ),
                    )
                  : profileLevelStrip(
                      inner!['level'] as int,
                      (inner['expTotal'] as int?) ?? 0,
                    ),
              isBot: isBot,
              onCloseDialog: () => Navigator.pop(ctx),
              placeholderBackground: placeholderBackground,
              placeholderForeground: placeholderForeground,
            ),
            content: SizedBox(
              width: contentWidth,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: contentMaxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Replaces the card outline: the header and the records
                    // still need to read as two things.
                    Container(height: 1, color: const Color(0xFFEFE6E1)),
                    const SizedBox(height: 10),
                    if (isBot)
                      botProfileBody(ctx)
                    else if (isLoading)
                      const SizedBox(
                        height: 140,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else
                      Flexible(
                        child: SingleChildScrollView(
                          child: PlayerProfileBody(
                            data: profile!,
                            game: game,
                            initialGame: initialGame ?? kProfileAllGamesTab,
                          ),
                        ),
                      ),
                  ],
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
