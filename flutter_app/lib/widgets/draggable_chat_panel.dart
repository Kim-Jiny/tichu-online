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

  /// Reads saved geometry into memory before any panel is built, so the first
  /// open of a session doesn't paint the default size first.
  static Future<void> preloadGeometry({String persistKey = 'chat'}) =>
      _DraggableChatPanelState.preload(persistKey: persistKey);

  @override
  State<DraggableChatPanel> createState() => _DraggableChatPanelState();
}

/// Panel geometry as last left by the user.
class _ChatGeometry {
  final double left;
  final double top;
  final double width;
  final double height;
  final double opacity;

  const _ChatGeometry(this.left, this.top, this.width, this.height, this.opacity);
}

class _DraggableChatPanelState extends State<DraggableChatPanel> {
  /// Saved geometry, per persistKey, held for the life of the app.
  ///
  /// SharedPreferences is async, so reading it in initState paints one frame at
  /// the default size before jumping to the saved one — reopening chat in a game
  /// visibly snapped. The first read fills this map; every open after that
  /// applies the size synchronously, and [preload] does the first read at
  /// startup so even that one doesn't flash.
  static final Map<String, _ChatGeometry> _cache = {};

  /// Warms the cache before any panel is built. Safe to call more than once.
  static Future<void> preload({String persistKey = 'chat'}) async {
    if (_cache.containsKey(persistKey)) return;
    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble('chat_panel_${persistKey}_left');
    final top = prefs.getDouble('chat_panel_${persistKey}_top');
    final width = prefs.getDouble('chat_panel_${persistKey}_width');
    final height = prefs.getDouble('chat_panel_${persistKey}_height');
    final opacity = prefs.getDouble('chat_panel_${persistKey}_opacity') ?? 1.0;
    if (left != null && top != null && width != null && height != null) {
      _cache[persistKey] = _ChatGeometry(left, top, width, height, opacity);
    }
  }

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

  // Panel opacity (1.0 = opaque). Clamped to [_minOpacity, 1] so it can never
  // become fully invisible/unreachable.
  static const double _minOpacity = 0.3;
  double _opacity = 1.0;
  bool _showOpacitySlider = false;

  String get _kLeft => 'chat_panel_${widget.persistKey}_left';
  String get _kTop => 'chat_panel_${widget.persistKey}_top';
  String get _kWidth => 'chat_panel_${widget.persistKey}_width';
  String get _kHeight => 'chat_panel_${widget.persistKey}_height';
  String get _kOpacity => 'chat_panel_${widget.persistKey}_opacity';

  @override
  void initState() {
    super.initState();
    // Cached from a previous open (or from preload at startup): apply before
    // the first frame so the panel never appears at the wrong size.
    final cached = _cache[widget.persistKey];
    if (cached != null) {
      _left = cached.left;
      _top = cached.top;
      _width = cached.width;
      _height = cached.height;
      _opacity = cached.opacity.clamp(_minOpacity, 1.0);
    } else {
      _loadGeometry();
    }
  }

  Future<void> _loadGeometry() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    // Opacity persists independently of geometry, so apply it even when no
    // saved position exists yet.
    final opacity = prefs.getDouble(_kOpacity);
    final left = prefs.getDouble(_kLeft);
    final top = prefs.getDouble(_kTop);
    final width = prefs.getDouble(_kWidth);
    final height = prefs.getDouble(_kHeight);
    setState(() {
      if (opacity != null) _opacity = opacity.clamp(_minOpacity, 1.0);
      // Don't clobber geometry the user already changed before prefs resolved.
      if (_left == null &&
          left != null &&
          top != null &&
          width != null &&
          height != null) {
        _left = left;
        _top = top;
        _width = width;
        _height = height;
      }
    });
    if (_left != null && _top != null && _width != null && _height != null) {
      _cache[widget.persistKey] = _ChatGeometry(
        _left!,
        _top!,
        _width!,
        _height!,
        _opacity,
      );
    }
  }

  Future<void> _saveGeometry() async {
    if (_left != null && _top != null && _width != null && _height != null) {
      _cache[widget.persistKey] = _ChatGeometry(
        _left!,
        _top!,
        _width!,
        _height!,
        _opacity,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    if (_left != null) await prefs.setDouble(_kLeft, _left!);
    if (_top != null) await prefs.setDouble(_kTop, _top!);
    if (_width != null) await prefs.setDouble(_kWidth, _width!);
    if (_height != null) await prefs.setDouble(_kHeight, _height!);
  }

  Future<void> _saveOpacity() async {
    final geo = _cache[widget.persistKey];
    if (geo != null) {
      _cache[widget.persistKey] = _ChatGeometry(
        geo.left,
        geo.top,
        geo.width,
        geo.height,
        _opacity,
      );
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kOpacity, _opacity);
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  /// How much of the screen the keyboard covers, in logical pixels.
  ///
  /// Not just MediaQuery: every board sits in a Scaffold with
  /// `resizeToAvoidBottomInset: false` (so the table doesn't jump when the
  /// keyboard opens), and that Scaffold strips the bottom inset from its
  /// body's MediaQuery. The panel therefore saw 0 and happily sat underneath
  /// the keyboard. The window itself still knows, so ask it too.
  double _keyboardInset(BuildContext context, MediaQueryData media) {
    final fromMedia = media.viewInsets.bottom;
    final view = View.of(context);
    final ratio = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    final fromView = view.viewInsets.bottom / ratio;
    return fromMedia > fromView ? fromMedia : fromView;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenW = media.size.width;
    final screenH = media.size.height;
    final topInset = media.padding.top;
    final keyboard = _keyboardInset(context, media);

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
        Opacity(
          opacity: _opacity,
          child: Container(
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
              if (_showOpacitySlider) _buildOpacitySlider(),
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
            (media.size.height -
                    _keyboardInset(context, media) -
                    height -
                    _margin)
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
              onTap: () =>
                  setState(() => _showOpacitySlider = !_showOpacitySlider),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 36,
                height: 32,
                child: Center(
                  child: Icon(
                    Icons.opacity,
                    color: _showOpacitySlider ? Colors.white : Colors.white70,
                    size: 19,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 2),
            GestureDetector(
              onTap: widget.onClose,
              behavior: HitTestBehavior.opaque,
              child: const SizedBox(
                width: 36,
                height: 32,
                child: Center(
                  child: Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Opacity gauge — only shown while toggled on via the header button.
  Widget _buildOpacitySlider() {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.opacity, size: 15, color: Color(0xFF8A8A8A)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 7),
              ),
              child: Slider(
                value: _opacity,
                min: _minOpacity,
                max: 1.0,
                activeColor: widget.accentColor,
                onChanged: (v) => setState(() => _opacity = v),
                onChangeEnd: (_) => _saveOpacity(),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${(_opacity * 100).round()}%',
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A8A)),
            ),
          ),
        ],
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
