import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Pulls the handful of images that appear on almost every screen into the
/// image cache before anything asks to draw them.
///
/// Why this exists: `Image.asset` does not fetch until the widget is laid out.
/// On a phone that costs nothing — the bytes are already on disk. On the web
/// each one is an HTTP request, and the server is in Europe, so a request
/// costs ~300ms of round trip no matter how small the file is (a 2-byte
/// /health reply measures the same as an 18KB avatar). The visible result was
/// a waiting room that drew, then filled in its bot faces a third of a second
/// later.
///
/// Shrinking the files does not help — the bytes were never the cost. Asking
/// early does: these go out in parallel, while the player is still reading the
/// lobby, and are decoded by the time a room needs them.
///
/// Kept deliberately short. Every entry is a request competing with whatever
/// the current screen actually needs, so this is for art that shows up almost
/// immediately and almost always — not for the whole card deck.
const List<String> _commonAssets = [
  // Six bot avatars: any room with a bot shows one, and filling a room with
  // bots is the most common way to start a game.
  'assets/bots/bot1.webp',
  'assets/bots/bot2.webp',
  'assets/bots/bot3.webp',
  'assets/bots/bot4.webp',
  'assets/bots/bot5.webp',
  'assets/bots/bot6.webp',
];

/// Fire-and-forget. Failures are ignored on purpose: a missing precache is a
/// slower first paint of that image, never a broken screen — `Image.asset`
/// still fetches it the normal way.
void precacheCommonImages(BuildContext context) {
  // Native already has these locally; precaching would only spend memory
  // decoding them before anything needs them.
  if (!kIsWeb) return;
  for (final path in _commonAssets) {
    precacheImage(AssetImage(path), context).catchError((_) {});
  }
}
