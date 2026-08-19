import 'dart:async';
import 'dart:math' as math;

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
    this.opaque = false,
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
  static const _fillOpaque = Color(0xFFFFFFFF);
  static const _border = Color(0xFFE6DDD8);
  static const tailHeight = 6.0;

  /// Board bubbles sit over cards and seats, so translucency made them hard to
  /// read; waiting-room seats keep it so the banner underneath still shows.
  final bool opaque;

  Color get _bodyFill => opaque ? _fillOpaque : _fill;

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _bodyFill,
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
              painter: _TailPainter(_bodyFill),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hangs a board seat's chat bubble above the seat, drawn on the overlay so
/// nothing on the board can cover it.
///
/// The bubble used to live inside the seat's own [Stack]. That put it in the
/// seat's layer, so any sibling drawn later — the next seat, the played-card
/// layer, a profile card — painted straight over it and the line was lost.
/// Going through the overlay puts it above the whole board instead, and a
/// [LayerLink] keeps it glued to the seat as the layout moves.
class SeatBubbleAnchor extends StatefulWidget {
  const SeatBubbleAnchor({
    super.key,
    required this.child,
    required this.text,
    this.suppressed = false,
    this.maxWidth = 178,
    this.fontSize = 11,
    this.maxLines = 1,
    this.gap = 2,
  });

  /// The seat the bubble belongs to.
  final Widget child;

  /// What that player just said, or null when nothing is showing.
  final String? text;

  /// Hides the bubble while the chat panel is open. The panel already shows
  /// the same line, and a bubble floating over the panel reads wrong — the
  /// overlay puts it above everything in the route, panel included.
  final bool suppressed;

  final double maxWidth;
  final double fontSize;
  final int maxLines;

  /// Space between the seat's top edge and the bubble's tail.
  final double gap;

  @override
  State<SeatBubbleAnchor> createState() => _SeatBubbleAnchorState();
}

class _SeatBubbleAnchorState extends State<SeatBubbleAnchor> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();

  /// 화면 안에 들어가도록 좁힌 최대폭. 좌석이 어디 앉았는지 알아야 정해지므로
  /// 레이아웃이 끝난 뒤에 계산한다.
  double? _fitWidth;

  /// 가장자리에서 이만큼은 띄운다.
  static const _edgeInset = 6.0;

  /// 아무리 좁혀도 이 아래로는 안 줄인다 — 그보다 좁으면 글자가 한 자도
  /// 안 남는다. 여기까지 왔다면 살짝 넘치더라도 읽히는 쪽이 낫다.
  static const _minWidth = 96.0;

  @override
  void didUpdateWidget(covariant SeatBubbleAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text
        || oldWidget.suppressed != widget.suppressed) {
      _scheduleSync();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  /// Toggling the portal marks it dirty, and both entry points here run inside
  /// a build (initState / didUpdateWidget) — so it waits for the frame to end.
  /// The follower also needs one laid-out frame before it has a target.
  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted) return;
    _measure();
    final wanted = widget.text != null && !widget.suppressed;
    if (wanted == _portal.isShowing) return;
    if (wanted) {
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  /// 말풍선은 좌석 한가운데에 맞춰 걸린다. 그래서 좌석이 화면 가장자리에
  /// 앉으면 기본 폭(178)이 그대로 화면 밖으로 넘어간다 — 티츄 보드의 좌/우
  /// 좌석이 딱 그 자리라, 긴 문장의 앞글자가 잘려 나갔다.
  ///
  /// 옆으로 밀어서 피할 수는 없다. 꼬리가 좌석을 가리키는 게 이 말풍선의
  /// 존재 이유라(좌석이 다닥다닥 붙어 있어 누가 한 말인지 그걸로 구분한다),
  /// 대신 양쪽으로 펼칠 수 있는 만큼만 폭을 준다. 넘치는 글자는 원래대로
  /// ... 로 잘린다.
  void _measure() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final centre = box.localToGlobal(Offset(box.size.width / 2, 0)).dx;
    final room = 2 * (math.min(centre, screenWidth - centre) - _edgeInset);
    final fit = math.min(widget.maxWidth, math.max(room, _minWidth));
    if (_fitWidth != null && (_fitWidth! - fit).abs() < 0.5) return;
    setState(() => _fitWidth = fit);
  }

  @override
  void dispose() {
    if (_portal.isShowing) _portal.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) {
          final text = widget.text;
          if (text == null || widget.suppressed) return const SizedBox.shrink();
          // Positioned so the overlay hands down LOOSE constraints. Without it
          // the overlay's tight full-screen box wins over the maxWidth here,
          // the bubble inflates to screen size, and pinning its bottom-centre
          // to the seat throws it clean off the top of the screen — it builds
          // but never shows.
          return Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _link,
              // Bubble's bottom-centre pinned just above the seat's top-centre.
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: Offset(0, -widget.gap),
              child: IgnorePointer(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: _fitWidth ?? widget.maxWidth),
                  child: SeatChatBubble(
                    text: text,
                    fontSize: widget.fontSize,
                    maxLines: widget.maxLines,
                    textAlign: TextAlign.center,
                    tail: true,
                    opaque: true,
                  ),
                ),
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _TailPainter extends CustomPainter {
  const _TailPainter(this.fill);

  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    // Cover the body's border where the tail joins it.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 2),
      Paint()..color = fill,
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
  bool shouldRepaint(covariant _TailPainter oldDelegate) => oldDelegate.fill != fill;
}
