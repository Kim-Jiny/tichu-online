import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';
import '../utils/banner_ink.dart';
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
          // to whatever the widest chip happened to be. 480 is where the stat
          // cards stop gaining anything from more room; +32 for the padding
          // that sits either side of them.
          final media = MediaQuery.of(ctx).size;
          final dialogWidth = math.max(272.0, math.min(media.width - 32, 512.0));
          // Header, actions and inset come off the top before the records get
          // their share.
          final available = (media.height - 190).clamp(220.0, 680.0);
          final contentMaxHeight = maxHeight == null
              ? available
              : math.min(maxHeight, available);

          // The banner they equipped, as the popup's background. It is already
          // the fill behind their seat in the lobby and in all four games; the
          // popup was the one place their own banner never showed up. The
          // gradient comes from the server's visual catalog, so an admin
          // editing a banner's stops changes this too.
          final inner = profile?['profile'] as Map?;
          final bannerKey = isBot ? null : inner?['bannerKey'] as String?;
          final banner = game.bannerGradient(bannerKey);
          final ink = banner == null
              ? null
              : profileBannerInk(banner, game.bannerTextColor(bannerKey));

          // On a banner the records move onto their own near-opaque sheet.
          // Stat cards, chips and match rows are all built for a light
          // background and there are far too many of them to recolour per
          // banner; the sheet lets the banner be the background — visible as
          // the header and as a frame around the records — without any of that
          // having to change.
          final sheetInset = banner == null
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(8, 0, 8, 8);
          final sheetPadding = banner == null
              ? const EdgeInsets.fromLTRB(16, 0, 16, 0)
              : const EdgeInsets.fromLTRB(8, 8, 8, 4);

          return Dialog(
            // Narrower inset than Material's default 40: at 40 a phone leaves
            // about 216dp of usable width, which is not enough for the three
            // action buttons to sit on one line.
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: dialogWidth,
              decoration: BoxDecoration(
                gradient: banner,
                color: banner == null ? const Color(0xFFFDFBFA) : null,
                borderRadius: BorderRadius.circular(22),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    // The header sits on the dialog itself. It used to be a
                    // bordered card inside the dialog — a frame drawn inside a
                    // frame, costing 28dp of width for no information.
                    child: PlayerProfileHeader(
                      nickname: nickname,
                      profile: profile,
                      game: game,
                      subtitle: subtitle ?? l10n.lobbyPlayerProfile,
                      // A private profile sends no level, and the strip's
                      // fallback ("Lv.1 0/100") reads as a real level rather
                      // than as a blank.
                      subtitleBuilder: (p) => p?['level'] == null
                          ? Text(
                              subtitle ?? l10n.lobbyPlayerProfile,
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    ink?.withValues(alpha: 0.78) ??
                                    const Color(0xFF84766E),
                              ),
                            )
                          : profileLevelStrip(
                              p!['level'] as int,
                              (p['expTotal'] as int?) ?? 0,
                              ink: ink,
                            ),
                      isBot: isBot,
                      onCloseDialog: () => Navigator.pop(ctx),
                      placeholderBackground: placeholderBackground,
                      placeholderForeground: placeholderForeground,
                      ink: ink,
                    ),
                  ),
                  Flexible(
                    child: Container(
                      margin: sheetInset,
                      padding: sheetPadding,
                      decoration: BoxDecoration(
                        color: banner == null
                            ? null
                            : Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Without a banner there is no sheet edge to separate
                          // the header from the records, so the hairline that
                          // used to do it stays.
                          if (banner == null) ...[
                            Container(height: 1, color: const Color(0xFFEFE6E1)),
                            const SizedBox(height: 10),
                          ],
                          if (isBot)
                            botProfileBody(ctx)
                          else if (isLoading)
                            const SizedBox(
                              height: 140,
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            Flexible(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: contentMaxHeight,
                                ),
                                child: SingleChildScrollView(
                                  child: PlayerProfileBody(
                                    data: profile!,
                                    game: game,
                                    initialGame:
                                        initialGame ?? kProfileAllGamesTab,
                                  ),
                                ),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(l10n.commonClose),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
