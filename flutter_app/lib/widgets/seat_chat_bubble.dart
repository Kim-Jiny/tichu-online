import 'dart:async';

import 'package:flutter/material.dart';

import '../services/game_service.dart';

/// Keeps the last thing each player said, for a couple of seconds, so a chat
/// line is visible on the seat itself without opening the chat panel.
///
/// Lives outside the screens because four of them draw a waiting room (the
/// room view, the spectator room, and the Mighty/SK/LL boards before the deal)
/// and all four want the same behaviour.
///
/// Only lines that arrive live raise a bubble: [GameService.liveChatSeq] does
/// not move when history is replayed, so joining a room — or a spectator taking
/// a seat — no longer pops the whole backlog as if it had just been typed.
class SeatChatBubbles {
  SeatChatBubbles(this._onChanged);

  /// Called when a bubble appears or expires; wire it to setState.
  final VoidCallback _onChanged;

  static const duration = Duration(milliseconds: 2200);

  final Map<String, String> _texts = {};
  final Map<String, Timer> _timers = {};
  int _seq = -1;

  /// Call from build. Cheap when nothing new has arrived.
  void consume(GameService game) {
    final seq = game.liveChatSeq;
    if (_seq < 0 || seq < _seq) {
      // First sight of this screen (or the log was reset): everything already
      // in it was said before we got here.
      _seq = seq;
      return;
    }
    if (seq == _seq) return;
    final delta = seq - _seq;
    _seq = seq;
    final messages = game.chatMessages;
    final fresh = messages.length >= delta
        ? messages.sublist(messages.length - delta)
        : messages;
    var changed = false;
    for (final m in fresh) {
      final sender = (m['sender'] ?? '') as String;
      final text = (m['message'] ?? '') as String;
      // System lines carry no sender, and a chat-ban notice is for its
      // recipient alone — neither belongs on a seat.
      if (sender.isEmpty || text.isEmpty || text == 'chat_banned') continue;
      if (game.isBlocked(sender)) continue;
      _timers[sender]?.cancel();
      _texts[sender] = text;
      _timers[sender] = Timer(duration, () {
        _texts.remove(sender);
        _timers.remove(sender);
        _onChanged();
      });
      changed = true;
    }
    // Arrived mid-build, so the bubble goes up on the next frame.
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onChanged());
    }
  }

  String? textFor(String nickname) => _texts[nickname];

  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _texts.clear();
  }
}

/// The bubble itself: translucent white over the seat, so the banner and the
/// nickname underneath still read as the same seat.
class SeatChatBubble extends StatelessWidget {
  const SeatChatBubble({
    super.key,
    required this.text,
    this.fontSize = 13,
    this.textAlign = TextAlign.start,
    this.maxLines = 2,
  });

  final String text;
  final double fontSize;
  final TextAlign textAlign;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFE6DDD8)),
        ),
        child: Text(
          text,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF4A3A32),
          ),
        ),
      ),
    );
  }
}
