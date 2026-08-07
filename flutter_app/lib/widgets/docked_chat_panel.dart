import 'package:flutter/material.dart';

import 'chat_panel_body.dart';

/// Chat as part of the page rather than on top of it: a fixed strip at the
/// bottom of the waiting room, under the start/ready button.
///
/// This is the default there. The floating panel is the right shape over a
/// board, where every pixel of table matters and the chat has to get out of
/// the way — but in a waiting room there is nothing underneath worth hiding,
/// and a chat you have to open, drag and close to read is a chat nobody
/// reads. [onUndock] hands it back to the floating panel for anyone who
/// preferred that.
///
/// No drag, resize or opacity here on purpose: those exist to work around
/// covering something, and a docked panel covers nothing.
class DockedChatPanel extends StatelessWidget {
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
  });

  /// Fills whatever box it is given — the caller decides how much is left
  /// after the seats.
  @override
  Widget build(BuildContext context) {
    return Container(
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
              scrollController: scrollController,
              controller: controller,
              hintText: hintText,
              onSend: onSend,
              sendIconColor: sendIconColor,
              itemCount: itemCount,
              itemBuilder: itemBuilder,
              onTapMessages: () => FocusScope.of(context).unfocus(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      color: accentColor,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          GestureDetector(
            onTap: onUndock,
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
    );
  }
}
