import 'package:flutter/material.dart';

import 'chat_panel_body.dart';

/// Chat as part of the page rather than on top of it: a strip at the bottom of
/// the waiting room, under the start/ready button.
///
/// This is the default there. The floating panel is the right shape over a
/// board, where every pixel of table matters and the chat has to get out of
/// the way — but in a waiting room there is nothing underneath worth hiding,
/// and a chat you have to open, drag and close to read is a chat nobody
/// reads. [onUndock] hands it back to the floating panel for anyone who
/// preferred that.
///
/// No move or opacity control here on purpose: those exist to work around
/// covering something, and a docked panel covers nothing. Height is the one
/// thing worth adjusting, since it is taken from the seats — drag the header.
class DockedChatPanel extends StatefulWidget {
  final Color accentColor;
  final Color sendIconColor;
  final String title;
  final String hintText;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;

  /// Pop out into the floating panel.
  final VoidCallback onUndock;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Dragging the header reports the height the user is asking for, in
  /// logical pixels. The caller decides what to do with it — it can only ask,
  /// because only the caller knows what the seats above still need.
  final ValueChanged<double>? onResize;

  /// Drag finished; a good moment to persist whatever [onResize] last sent.
  final VoidCallback? onResizeEnd;

  const DockedChatPanel({
    super.key,
    required this.accentColor,
    required this.sendIconColor,
    required this.title,
    required this.hintText,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    required this.onUndock,
    required this.itemCount,
    required this.itemBuilder,
    this.onResize,
    this.onResizeEnd,
  });

  @override
  State<DockedChatPanel> createState() => _DockedChatPanelState();
}

class _DockedChatPanelState extends State<DockedChatPanel> {
  final GlobalKey _boxKey = GlobalKey();

  /// The height being asked for, carried across a drag. Seeded from what the
  /// panel actually measures at drag start rather than from a remembered
  /// value: the caller may be giving it more than it asked for (the chat
  /// fills whatever the seats leave), and starting from the remembered value
  /// would make the panel jump to that on the first pixel of movement.
  double? _dragHeight;

  void _onDragStart(DragStartDetails _) {
    final box = _boxKey.currentContext?.findRenderObject() as RenderBox?;
    _dragHeight = box?.hasSize == true ? box!.size.height : null;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final current = _dragHeight;
    final onResize = widget.onResize;
    if (current == null || onResize == null) return;
    // Up is a taller chat, so the delta goes in negated.
    _dragHeight = current - details.delta.dy;
    onResize(_dragHeight!);
  }

  void _onDragEnd(DragEndDetails _) {
    _dragHeight = null;
    widget.onResizeEnd?.call();
  }

  /// Fills whatever box it is given — the caller decides how much is left
  /// after the seats.
  @override
  Widget build(BuildContext context) {
    return Container(
      key: _boxKey,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: ChatPanelBody(
              scrollController: widget.scrollController,
              controller: widget.controller,
              hintText: widget.hintText,
              onSend: widget.onSend,
              sendIconColor: widget.sendIconColor,
              itemCount: widget.itemCount,
              itemBuilder: widget.itemBuilder,
              onTapMessages: () => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  /// The title bar, which is also the resize grip. Dragging the top edge is
  /// how every panel like this resizes, and the bar is a far easier target
  /// than the 1px edge itself.
  Widget _buildHeader() {
    final resizable = widget.onResize != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: resizable ? _onDragStart : null,
      onVerticalDragUpdate: resizable ? _onDragUpdate : null,
      onVerticalDragEnd: resizable ? _onDragEnd : null,
      child: Container(
        padding: const EdgeInsets.only(left: 10, right: 4),
        color: widget.accentColor,
        child: Row(
          children: [
            if (resizable) ...[
              const Icon(Icons.drag_handle, color: Colors.white70, size: 18),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            GestureDetector(
              onTap: widget.onUndock,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                width: 36,
                height: 32,
                child: Center(
                  child: Icon(Icons.open_in_new, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
