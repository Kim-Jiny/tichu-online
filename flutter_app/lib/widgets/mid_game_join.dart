import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/game_service.dart';

/// Breaking into, and walking out of, a match that is already running.
///
/// Both directions live behind one room option, so they share a file: a room
/// that lets people in has to let them out, and the UI for the two mirrors.
/// Every widget here self-hides when the action isn't available, so screens
/// can mount them unconditionally instead of duplicating the eligibility rules.

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
            const Icon(Icons.login, size: 13, color: Colors.white),
            const SizedBox(width: 4),
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

/// Ask, then walk out — hand the seat to a bot and leave the running match.
///
/// A standalone function so a game screen's existing "leave" dialog can offer
/// this as a second exit without having to restate the warning: every screen
/// spells out the same two costs (it goes on your record, and it locks you out
/// of joining another match for a while) because they come from one place.
Future<void> confirmMidGameLeave(BuildContext context, GameService game) async {
  final l10n = L10n.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(l10n.midLeaveConfirmTitle),
      content: Text(l10n.midLeaveConfirmBody(kMidGameJoinCooldownMinutes)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.gameClose),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFD24B4B),
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.midLeaveConfirmOk),
        ),
      ],
    ),
  );
  if (ok != true) return;
  // Re-check after the dialog: the last other human may have left while it was
  // open, in which case walking out is no longer allowed.
  if (!game.canLeaveInProgress) return;
  game.leaveInProgress();
}

/// "Walk out" — a seated player handing their seat to a bot mid-match.
///
/// Hidden unless the room allows it and another human is still at the table,
/// matching the server's refusal rather than surfacing a button that errors.
/// The confirm spells out both costs: it goes on your record, and it locks you
/// out of joining another match for a while.
class MidGameLeaveButton extends StatelessWidget {
  final GameService game;

  /// Renders as a plain list tile instead of a pill, for in-game menus.
  final bool asMenuTile;

  const MidGameLeaveButton({
    super.key,
    required this.game,
    this.asMenuTile = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!game.canLeaveInProgress) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    if (asMenuTile) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.logout, size: 20, color: Color(0xFFD24B4B)),
        title: Text(
          l10n.midLeaveButton,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFFD24B4B),
          ),
        ),
        onTap: () => confirmMidGameLeave(context, game),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => confirmMidGameLeave(context, game),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE6C4C4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.logout, size: 13, color: Color(0xFFD24B4B)),
            const SizedBox(width: 4),
            Text(
              l10n.midLeaveButton,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFFD24B4B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

