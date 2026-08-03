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
    this.tail = false,
  });

  final String text;
  final double fontSize;
  final TextAlign textAlign;
  final int maxLines;

  /// A little spike under the bubble, pointing at the seat it belongs to.
  /// Board seats sit close together, and without it a bubble floating between
  /// two of them could be read as either one's.
  final bool tail;

  static const _fill = Color(0xE1FFFFFF); // white, 88%
  static const _border = Color(0xFFE6DDD8);
  static const tailHeight = 6.0;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _border),
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
    );
    if (!tail) return IgnorePointer(child: body);
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          body,
          // Pulled up by a pixel so its base paints over the body's bottom
          // border — otherwise a line runs across where the two meet.
          Transform.translate(
            offset: const Offset(0, -1),
            child: CustomPaint(
              size: const Size(12, tailHeight),
              painter: _TailPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = SeatChatBubble._fill);
    // Cover the body's border where the tail joins it.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 2),
      Paint()..color = SeatChatBubble._fill,
    );
    final edge = Paint()
      ..color = SeatChatBubble._border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawLine(
      const Offset(0, 0),
      Offset(size.width / 2, size.height),
      edge,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width / 2, size.height),
      edge,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
