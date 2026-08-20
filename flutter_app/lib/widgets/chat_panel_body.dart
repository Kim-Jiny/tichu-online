import 'package:flutter/material.dart';

/// The two halves every chat panel has in common: the reversed message list
/// and the composer under it.
///
/// Split out when the waiting room gained a docked chat. The docked and the
/// floating panel differ only in their shell — one sits in the layout, the
/// other drags and fades — and keeping two copies of the list and the input
/// row is how the per-screen chat wrappers already drifted apart.
class ChatPanelBody extends StatefulWidget {
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

  /// 전송 버튼 오른쪽으로 비워 둘 폭.
  ///
  /// 떠 있는 패널은 오른쪽 아래 모서리에 리사이즈 손잡이를 얹는데, 그게
  /// 전송 버튼 위에 겹쳐 앉아 탭을 가로챘다 — 버튼을 눌러도 아무 일이 없거나
  /// (손잡이엔 onTap 이 없다) 손가락이 조금만 움직이면 onPanStart 가 물려
  /// 키보드만 내려갔다. 손잡이가 앉을 자리를 비워 둬서 둘이 안 겹치게 한다.
  final double trailingInset;

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
    this.trailingInset = 0,
  });

  @override
  State<ChatPanelBody> createState() => _ChatPanelBodyState();
}

class _ChatPanelBodyState extends State<ChatPanelBody> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// 엔터로 보낸 뒤에도 계속 칠 수 있어야 한다. 한 줄짜리 TextField 는 제출을
  /// 처리하고 나서 포커스를 놓기 때문에, 여기서 곧바로 다시 잡으면 그 해제에
  /// 덮인다 — 프레임이 끝난 뒤에 잡는다.
  ///
  /// 채팅은 한 마디로 끝나는 일이 드물다. 한 줄 보낼 때마다 입력창을 다시
  /// 눌러야 하는 건, 키보드가 있는 웹에서 특히 걸린다.
  void _sendKeepingFocus() {
    widget.onSend();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTapMessages,
            child: ListView.builder(
              controller: widget.scrollController,
              reverse: true,
              padding: const EdgeInsets.all(8),
              itemCount: widget.itemCount,
              itemBuilder: widget.itemBuilder,
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
                  controller: widget.controller,
                  focusNode: _focus,
                  decoration: InputDecoration(
                    hintText: widget.hintText,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onSubmitted: (_) => _sendKeepingFocus(),
                ),
              ),
              // 입력창의 "바깥"으로 치지 않게 묶는다.
              //
              // TextField 는 바깥을 탭하면 포커스를 놓는데, 바로 옆 전송
              // 버튼도 바깥이다. 웹에서는 이게 실제로 동작해서(모바일 터치는
              // 예외 — EditableTextTapOutsideIntent 참고) 버튼으로 보낼 때마다
              // 커서가 사라졌다. 엔터로 보낼 때 커서를 남기기로 한 것과 같은
              // 이유로, 버튼도 커서를 뺏지 않는 게 맞다.
              TextFieldTapRegion(
                child: IconButton(
                  onPressed: widget.onSend,
                  icon: Icon(Icons.send, color: widget.sendIconColor),
                ),
              ),
              if (widget.trailingInset > 0)
                SizedBox(width: widget.trailingInset),
            ],
          ),
        ),
      ],
    );
  }
}
