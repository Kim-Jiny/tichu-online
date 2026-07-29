import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/screens/photo_crop_screen.dart';

/// The crop maps a viewport square back through a pan/zoom matrix into source
/// pixels — arithmetic that reads fine and is easy to get subtly wrong (off by
/// the cover scale, or by the centring translation), and impossible to eyeball
/// from the rendered result.
///
/// Plain `test`, not `testWidgets`: the latter runs under FakeAsync, where
/// decodeImageFromList and Picture.toImage never complete.

/// A [width]x[height] image split into vertical colour bands, left to right.
Future<ui.Image> _banded(int width, int height, List<Color> bands) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final bandWidth = width / bands.length;
  for (var i = 0; i < bands.length; i++) {
    canvas.drawRect(
      Rect.fromLTWH(i * bandWidth, 0, bandWidth, height.toDouble()),
      Paint()..color = bands[i],
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

/// A [width]x[height] image painted from explicit (topFraction, colour) bands.
/// Explicit rather than evenly divided so a test can place a band exactly where
/// the crop is expected to land.
Future<ui.Image> _stripedAt(
    int width, int height, List<(double, double, Color)> stripes) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final (top, bottom, color) in stripes) {
    canvas.drawRect(
      Rect.fromLTRB(0, top, width.toDouble(), bottom),
      Paint()..color = color,
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

/// Colour at a fractional position, (0,0) top-left to (1,1) bottom-right.
Future<int> _pixelAt(Uint8List png, double fx, double fy) async {
  final image = await decodeImageFromList(png);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final x = (fx * (image.width - 1)).round();
  final y = (fy * (image.height - 1)).round();
  final o = (y * image.width + x) * 4;
  final b = data!.buffer.asUint8List();
  final argb = (b[o + 3] << 24) | (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];
  image.dispose();
  return argb;
}

/// The initial, untouched state the screen puts an image in: cover-scaled and
/// centred in a [viewport]-sided square. Mirrors _PhotoCropScreenState._layout.
Future<Uint8List?> _exportUntouched(ui.Image image, double viewport) async {
  final size = Size(image.width.toDouble(), image.height.toDouble());
  final cover = coverScaleFor(size, viewport);
  final transform = centredCoverTransform(
    Size(size.width * cover, size.height * cover),
    viewport,
  );
  final src = visibleSourceRect(
    transform: transform,
    viewport: viewport,
    coverScale: cover,
    imageSize: size,
  );
  return renderSquare(image, src);
}

const _red = 0xFFFF0000;
const _green = 0xFF00FF00;
const _blue = 0xFF0000FF;
const _yellow = 0xFFFFFF00;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cover scale is driven by the shorter side', () {
    // A wide image has to be scaled by its HEIGHT to still fill the square.
    expect(coverScaleFor(const Size(800, 400), 300), 300 / 400);
    expect(coverScaleFor(const Size(400, 800), 300), 300 / 400);
    expect(coverScaleFor(const Size(400, 400), 300), 300 / 400);
  });

  test('an untouched square source keeps every band, in order', () async {
    final image = await _banded(400, 400, const [
      Color(_red),
      Color(_green),
      Color(_blue),
      Color(_yellow),
    ]);
    final out = await _exportUntouched(image, 300);
    image.dispose();
    expect(out, isNotNull);
    expect(await _pixelAt(out!, 0.10, 0.5), _red);
    expect(await _pixelAt(out, 0.35, 0.5), _green);
    expect(await _pixelAt(out, 0.60, 0.5), _blue);
    expect(await _pixelAt(out, 0.90, 0.5), _yellow);
  });

  test('a wide source keeps the middle, not an edge', () async {
    // 800x400 in four bands: covering a square shows the middle half, i.e.
    // bands 2 and 3 only. A wrong centring translation surfaces 1 or 4 here.
    final image = await _banded(800, 400, const [
      Color(_red), // must NOT appear
      Color(_green),
      Color(_blue),
      Color(_yellow), // must NOT appear
    ]);
    final out = await _exportUntouched(image, 300);
    image.dispose();
    expect(out, isNotNull);
    expect(await _pixelAt(out!, 0.20, 0.5), _green);
    expect(await _pixelAt(out, 0.80, 0.5), _blue);
    expect(await _pixelAt(out, 0.02, 0.5), isNot(_red));
    expect(await _pixelAt(out, 0.98, 0.5), isNot(_yellow));
  });

  test('a tall source keeps the middle band, dropping top and bottom',
      () async {
    // 400x800: the crop is 400 tall and centred, so exactly y 200..600. Paint
    // that span green and the margins red/blue — anything but pure green in the
    // export means the vertical centring is off.
    final image = await _stripedAt(400, 800, const [
      (0, 200, Color(_red)),
      (200, 600, Color(_green)),
      (600, 800, Color(_blue)),
    ]);
    final out = await _exportUntouched(image, 300);
    image.dispose();
    expect(out, isNotNull);
    // Inset from the very edge: the crop boundary lands exactly on the colour
    // boundary, so the outermost row is a resampling blend of the two.
    expect(await _pixelAt(out!, 0.5, 0.02), _green);
    expect(await _pixelAt(out, 0.5, 0.50), _green);
    expect(await _pixelAt(out, 0.5, 0.98), _green);
  });

  test('the export is 512 square whatever went in', () async {
    final image = await _banded(800, 400, const [Color(_red)]);
    final out = await _exportUntouched(image, 300);
    image.dispose();
    final decoded = await decodeImageFromList(out!);
    expect(decoded.width, 512);
    expect(decoded.height, 512);
    decoded.dispose();
  });

  test('zooming in narrows the source rect around the same centre', () async {
    // 2x zoom about the centre should halve the visible region in both axes.
    const viewport = 300.0;
    const size = Size(400, 400);
    final cover = coverScaleFor(size, viewport);
    final base = centredCoverTransform(
        Size(size.width * cover, size.height * cover), viewport);
    final zoomed = base.clone()
      ..translateByDouble(size.width * cover / 2, size.height * cover / 2, 0, 1)
      ..scaleByDouble(2, 2, 1, 1)
      ..translateByDouble(
          -size.width * cover / 2, -size.height * cover / 2, 0, 1);

    final full = visibleSourceRect(
        transform: base,
        viewport: viewport,
        coverScale: cover,
        imageSize: size);
    final half = visibleSourceRect(
        transform: zoomed,
        viewport: viewport,
        coverScale: cover,
        imageSize: size);

    expect(full.width, closeTo(400, 0.01));
    expect(half.width, closeTo(200, 0.01));
    expect(half.height, closeTo(200, 0.01));
    expect(half.center.dx, closeTo(full.center.dx, 0.01));
    expect(half.center.dy, closeTo(full.center.dy, 0.01));
  });

  test('a rect outside the image is clamped, never sampled out of bounds',
      () async {
    const viewport = 300.0;
    const size = Size(400, 400);
    final cover = coverScaleFor(size, viewport);
    // Deliberately push the child far off; InteractiveViewer would not allow
    // this, but the clamp is the thing keeping drawImageRect honest if it did.
    final shoved = centredCoverTransform(
        Size(size.width * cover, size.height * cover), viewport)
      ..translateByDouble(-10000, -10000, 0, 1);
    final src = visibleSourceRect(
        transform: shoved,
        viewport: viewport,
        coverScale: cover,
        imageSize: size);
    expect(src.left, greaterThanOrEqualTo(0));
    expect(src.top, greaterThanOrEqualTo(0));
    expect(src.right, lessThanOrEqualTo(size.width));
    expect(src.bottom, lessThanOrEqualTo(size.height));
  });
}
