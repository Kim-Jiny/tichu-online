import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';

/// Breaking into a match that is already running.
///
/// The other direction needs no widget of its own: in a room with this option
/// on, the ordinary "leave" already hands your seat to a bot instead of ending
/// the match, so the exit is the button that was always there — only its
/// warning text changes. See [GameService.canLeaveInProgress].

/// Minutes of cooldown after touching a live match. Mirrors
/// `MID_GAME_JOIN_COOLDOWN_MS` on the server; shown in the walk-out warning so
/// the cost is stated before the tap, not after.
const int kMidGameJoinCooldownMinutes = 5;

/// "Join in progress" — a spectator taking over a bot seat in a running match.
///
/// Renders nothing unless the room allows it and a bot seat is actually free,
/// so every spectator header can mount it unconditionally.
class MidGameJoinButton extends StatelessWidget {
  final GameService game;

  const MidGameJoinButton({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    if (!game.canJoinInProgress) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(l10n.midJoinConfirmTitle),
            content: Text(l10n.midJoinConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.gameClose),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.midJoinConfirmOk),
              ),
            ],
          ),
        );
        if (ok != true) return;
        // Re-check rather than trusting the pre-dialog state: seats fill while
        // a dialog is open. The server refuses anyway; this avoids the error
        // toast for the common race.
        if (!game.canJoinInProgress) return;
        game.joinInProgress();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF4A4080),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The artwork, matching the mark on this room's lobby card and
            // the switch that turned the option on.
            Image.asset(
              'assets/icons/allowBotReplacement.webp',
              width: 18,
              height: 14,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 5),
            Text(
              l10n.midJoinButton,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
