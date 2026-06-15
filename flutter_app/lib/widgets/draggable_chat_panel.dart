import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A floating chat panel that the user can drag to reposition and resize,
/// with its position/size persisted across app restarts via SharedPreferences.
///
/// Shared by all game screens (Tichu / Love Letter / SK / spectator) so the
/// drag/resize/keyboard behaviour stays consistent. Each screen supplies its
/// own accent colour, strings and message-bubble builder.
///
/// Keyboard: tapping anywhere outside the panel (or on the message list)
/// dismisses the soft keyboard — fixing the "keyboard won't go down" issue on
/// screens that use `resizeToAvoidBottomInset: false`.
///
/// Must be placed as a direct child of a [Stack] (it returns a [Positioned]).
class DraggableChatPanel extends StatefulWidget {
  final Color accentColor;
  final Color sendIconColor;
  final String title;
  final String hintText;
  final TextEditingController controller;
  final ScrollController scrollController;
  final VoidCallback onSend;
  final VoidCallback onClose;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// SharedPreferences namespace for persisted geometry. A single shared key
  /// keeps the chat in the same spot across every game screen.
  final String persistKey;

  const DraggableChatPanel({
    super.key,
    required this.accentColor,
    required this.sendIconColor,
    required this.title,
    required this.hintText,
    required this.controller,
    required this.scrollController,
    required this.onSend,
    required this.onClose,
    required this.itemCount,
    required this.itemBuilder,
    this.persistKey = 'chat',
  });

  @override
  State<DraggableChatPanel> createState() => _DraggableChatPanelState();
}

class _DraggableChatPanelState extends State<DraggableChatPanel> {
  static const double _minWidth = 220;
  static const double _maxWidth = 360;
  static const double _minHeight = 160;
  static const double _maxHeight = 480;
  static const double _margin = 8;
  static const double _topGap = 42;

  // null until either the user has interacted or saved geometry is loaded;
  // build() falls back to a screen-relative default while null.
  double? _left;
  double? _top;
  double? _width;
  double? _height;

  String get _kLeft => 'chat_panel_${widget.persistKey}_left';
  String get _kTop => 'chat_panel_${widget.persistKey}_top';
  String get _kWidth => 'chat_panel_${widget.persistKey}_width';
  String get _kHeight => 'chat_panel_${widget.persistKey}_height';

  @override
  void initState() {
    super.initState();
    _loadGeometry();
  }

  Future<void> _loadGeometry() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Don't clobber geometry the user already changed before prefs resolved.
    if (_left != null) return;
    final left = prefs.getDouble(_kLeft);
    final top = prefs.getDouble(_kTop);
    final width = prefs.getDouble(_kWidth);
    final height = prefs.getDouble(_kHeight);
    if (left == null || top == null || width == null || height == null) {
      return;
    }
    setState(() {
      _left = left;
      _top = top;
      _width = width;
      _height = height;
    });
  }

  Future<void> _saveGeometry() async {
    final prefs = await SharedPreferences.getInstance();
    if (_left != null) await prefs.setDouble(_kLeft, _left!);
    if (_top != null) await prefs.setDouble(_kTop, _top!);
    if (_width != null) await prefs.setDouble(_kWidth, _width!);
    if (_height != null) await prefs.setDouble(_kHeight, _height!);
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final screenH = media.size.height;
    final topInset = media.padding.top;
    final keyboard = media.viewInsets.bottom;

    final maxW = (screenW - _margin * 2).clamp(_minWidth, _maxWidth);
    // Space between the top gap and the keyboard (or screen bottom).
    final available = screenH - (topInset + _topGap) - _margin - keyboard;
    final maxH = available.clamp(_minHeight, _maxHeight);

    final width = (_width ?? maxW).clamp(_minWidth, maxW);
    final height = (_height ?? 350.0).clamp(_minHeight, maxH);

    // Defaults: top-right corner under the toolbar.
    final defaultLeft = screenW - width - _margin;
    final defaultTop = topInset + _topGap;

    // Clamp into the visible area (above the keyboard).
    final minLeft = _margin;
    final maxLeft = (screenW - width - _margin).clamp(_margin, double.infinity);
    final minTop = topInset + _margin;
    final maxTop =
        (screenH - keyboard - height - _margin).clamp(minTop, double.infinity);

    final left = (_left ?? defaultLeft).clamp(minLeft, maxLeft);
    final top = (_top ?? defaultTop).clamp(minTop, maxTop);

    final keyboardOpen = keyboard > 0;

    return Positioned.fill(
      child: Stack(
        children: [
          // Tap-to-dismiss barrier — always present (so the children list
          // keeps a stable length/order and Flutter never re-matches the
          // panel's element to the barrier, which would destroy the focused
          // TextField and bounce the keyboard back down). IgnorePointer lets
          // touches pass through to gameplay whenever the keyboard is closed.
          Positioned.fill(
            key: const ValueKey('chat_dismiss_barrier'),
            child: IgnorePointer(
              ignoring: !keyboardOpen,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismissKeyboard,
              ),
            ),
          ),
          Positioned(
            key: const ValueKey('chat_panel'),
            left: left,
            top: top,
            width: width,
            height: height,
            child: _buildPanel(width, height, maxW, maxH),
          ),
        ],
      ),
    );
  }

  Widget _buildPanel(double width, double height, double maxW, double maxH) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildHeader(width, height),
              // Messages — tapping empty space dismisses the keyboard.
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _dismissKeyboard,
                  child: ListView.builder(
                    controller: widget.scrollController,
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: widget.itemCount,
                    itemBuilder: widget.itemBuilder,
                  ),
                ),
              ),
              // Input
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
                        decoration: InputDecoration(
                          hintText: widget.hintText,
                          border: InputBorder.none,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onSubmitted: (_) => widget.onSend(),
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onSend,
                      icon: Icon(Icons.send, color: widget.sendIconColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Resize handle (bottom-right corner).
        Positioned(
          right: 0,
          bottom: 0,
          child: _buildResizeHandle(width, height, maxW, maxH),
        ),
      ],
    );
  }

  Widget _buildHeader(double width, double height) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _dismissKeyboard(),
      onPanUpdate: (details) {
        final media = MediaQuery.of(context);
        final maxLeft = (media.size.width - width - _margin)
            .clamp(_margin, double.infinity);
        final minTop = media.padding.top + _margin;
        final maxTop =
            (media.size.height - media.viewInsets.bottom - height - _margin)
                .clamp(minTop, double.infinity);
        final curLeft = _left ?? (media.size.width - width - _margin);
        final curTop = _top ?? (media.padding.top + _topGap);
        setState(() {
          // Clamp as we drag so the internal value never drifts off-screen
          // (otherwise reversing direction leaves a dead zone).
          _left = (curLeft + details.delta.dx).clamp(_margin, maxLeft);
          _top = (curTop + details.delta.dy).clamp(minTop, maxTop);
          _width = width;
          _height = height;
        });
      },
      onPanEnd: (_) => _saveGeometry(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: widget.accentColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.drag_indicator, color: Colors.white70, size: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            GestureDetector(
              onTap: widget.onClose,
              child: const Icon(Icons.close, color: Colors.white, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResizeHandle(
      double width, double height, double maxW, double maxH) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => _dismissKeyboard(),
      onPanUpdate: (details) {
        setState(() {
          // Anchor top-left; grow toward bottom-right.
          _left ??= MediaQuery.of(context).size.width - width - _margin;
          _top ??= MediaQuery.of(context).padding.top + _topGap;
          _width = (width + details.delta.dx).clamp(_minWidth, maxW);
          _height = (height + details.delta.dy).clamp(_minHeight, maxH);
        });
      },
      onPanEnd: (_) => _saveGeometry(),
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.only(bottomRight: Radius.circular(16)),
        ),
        alignment: Alignment.bottomRight,
        padding: const EdgeInsets.all(6),
        child: Icon(
          Icons.open_in_full,
          size: 16,
          color: widget.accentColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
