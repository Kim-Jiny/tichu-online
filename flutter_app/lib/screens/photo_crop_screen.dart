/// Square crop for a profile photo, before it goes to the server.
///
/// The server squares whatever it receives with a centre `cover` crop, which
/// decapitates a lot of portraits. This lets the user say which square they
/// meant. Deliberately written against InteractiveViewer + dart:ui rather than
/// pulling in image_cropper: that package brings uCrop and TOCropViewController
/// with it, and this project has already lost time to CocoaPods/SPM conflicts
/// on iOS. Nothing here needs a platform channel.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Scale that makes [image] cover a [viewport]-sized square. `cover`, not
/// `contain`: it is what keeps the square full at every pan position, so the
/// export can never come back with blank corners.
double coverScaleFor(Size image, double viewport) {
  final byWidth = viewport / image.width;
  final byHeight = viewport / image.height;
  return byWidth > byHeight ? byWidth : byHeight;
}

/// Transform that centres a cover-scaled image in the square.
Matrix4 centredCoverTransform(Size scaledChild, double viewport) {
  return Matrix4.identity()
    ..translateByDouble((viewport - scaledChild.width) / 2,
        (viewport - scaledChild.height) / 2, 0, 1);
}

/// Which part of the SOURCE image the viewport square is showing.
///
/// Split out of the widget and exported because this is the part that is easy
/// to get subtly wrong — off by the cover scale, or by the centring
/// translation — and impossible to eyeball from the rendered result.
Rect visibleSourceRect({
  required Matrix4 transform,
  required double viewport,
  required double coverScale,
  required Size imageSize,
}) {
  final inverse = Matrix4.tryInvert(transform);
  if (inverse == null) return Rect.zero;
  // Viewport square -> child coordinates...
  final visible = MatrixUtils.transformRect(
    inverse,
    Rect.fromLTWH(0, 0, viewport, viewport),
  );
  // ...then child -> source pixels. Clamped because a fractional rounding out
  // of bounds makes drawImageRect sample garbage along the edge.
  return Rect.fromLTRB(
    (visible.left / coverScale).clamp(0, imageSize.width),
    (visible.top / coverScale).clamp(0, imageSize.height),
    (visible.right / coverScale).clamp(0, imageSize.width),
    (visible.bottom / coverScale).clamp(0, imageSize.height),
  );
}

/// Redraw [src] of [image] as a [size]² PNG.
Future<Uint8List?> renderSquare(ui.Image image, Rect src,
    {double size = 512}) async {
  if (src.width <= 0 || src.height <= 0) return null;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    image,
    src,
    Rect.fromLTWH(0, 0, size, size),
    Paint()..filterQuality = FilterQuality.high,
  );
  final picture = recorder.endRecording();
  ui.Image? out;
  try {
    out = await picture.toImage(size.toInt(), size.toInt());
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    out?.dispose();
    picture.dispose();
  }
}

/// Pops [Uint8List] PNG bytes of the chosen square, or null on cancel. PNG
/// because dart:ui only encodes to PNG; the server re-encodes to JPEG anyway.
class PhotoCropScreen extends StatefulWidget {
  final Uint8List bytes;
  const PhotoCropScreen({super.key, required this.bytes});

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  /// Edge of the exported square. Matches the server's own resize, so the
  /// round trip neither upscales nor throws away detail the user framed.
  static const double _outputSize = 512;

  final TransformationController _controller = TransformationController();
  ui.Image? _image;
  bool _failed = false;
  bool _busy = false;

  // Viewport edge and the scale that makes the image cover it. Recomputed on
  // layout so a rotation doesn't leave the transform describing a stale box.
  double _viewport = 0;
  double _coverScale = 1;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void dispose() {
    _controller.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    try {
      final image = await decodeImageFromList(widget.bytes);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Fit the image over the viewport and centre it.
  void _layout(double viewport) {
    final image = _image;
    if (image == null || viewport <= 0) return;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final cover = coverScaleFor(size, viewport);
    if (_viewport == viewport && _coverScale == cover) return;
    _viewport = viewport;
    _coverScale = cover;
    _controller.value = centredCoverTransform(
      Size(size.width * cover, size.height * cover),
      viewport,
    );
  }

  Future<Uint8List?> _export() async {
    final image = _image;
    if (image == null || _viewport <= 0) return null;
    final src = visibleSourceRect(
      transform: _controller.value,
      viewport: _viewport,
      coverScale: _coverScale,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    );
    return renderSquare(image, src, size: _outputSize);
  }

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bytes = await _export();
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _busy = false);
      return;
    }
    Navigator.pop(context, bytes);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.profilePhotoCropTitle),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _image == null || _busy ? null : _confirm,
            child: Text(
              l10n.commonConfirm,
              style: TextStyle(
                color: _image == null || _busy ? Colors.white38 : Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: _buildStage())),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Text(
              l10n.profilePhotoCropHint,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStage() {
    if (_failed) {
      return Text(
        L10n.of(context).profilePhotoUploadFailed,
        style: const TextStyle(color: Colors.white70),
      );
    }
    final image = _image;
    if (image == null) {
      return const CircularProgressIndicator(color: Colors.white);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        // During layout, not after: the first frame must already be centred or
        // the user sees the image jump.
        _layout(side);
        final childW = image.width * _coverScale;
        final childH = image.height * _coverScale;
        return SizedBox(
          width: side,
          height: side,
          child: ClipRect(
            child: InteractiveViewer(
              transformationController: _controller,
              // Zero margin is what forbids panning past the edges, so the
              // square stays covered and the export has no blank corners.
              boundaryMargin: EdgeInsets.zero,
              constrained: false,
              minScale: 1,
              maxScale: 5,
              child: SizedBox(
                width: childW,
                height: childH,
                child: RawImage(image: image, fit: BoxFit.fill),
              ),
            ),
          ),
        );
      },
    );
  }
}
