import 'package:flutter/material.dart';

/// The two halves every chat panel has in common: the reversed message list
/// and the composer under it.
///
/// Split out when the waiting room gained a docked chat. The docked and the
/// floating panel differ only in their shell — one sits in the layout, the
/// other drags and fades — and keeping two copies of the list and the input
/// row is how the per-screen chat wrappers already drifted apart.
class ChatPanelBody extends StatelessWidget {
  final ScrollController scrollController;
  final TextEditingController controller;
  final String hintText;
  final VoidCallback onSend;
  final Color sendIconColor;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Tapping empty space in the message list. The floating panel drops the
  /// keyboard here; it also has a full-screen barrier, but the list is the
  /// only reachable spot once the panel covers what's behind it.
  final VoidCallback onTapMessages;

  const ChatPanelBody({
    super.key,
    required this.scrollController,
    required this.controller,
    required this.hintText,
    required this.onSend,
    required this.sendIconColor,
    required this.itemCount,
    required this.itemBuilder,
    required this.onTapMessages,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onTapMessages,
            child: ListView.builder(
              controller: scrollController,
              reverse: true,
              padding: const EdgeInsets.all(8),
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: hintText,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              IconButton(
                onPressed: onSend,
                icon: Icon(Icons.send, color: sendIconColor),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
