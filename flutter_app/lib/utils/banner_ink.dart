import 'package:flutter/material.dart';

/// What colour of text will read on top of an equipped banner.
///
/// [override] is the admin-set `metadata.visual.text.color`, which is the
/// answer whenever it exists — someone looked at that banner and decided. It
/// often doesn't: the banners that shipped before that field, and anything an
/// admin adds without filling it in. Falling back to the popup's usual dark
/// brown puts near-invisible text on the dark banners, so the fallback is
/// decided by how bright the gradient actually is.
///
/// The whole gradient is averaged rather than sampled at one end. A banner
/// that runs dark-to-light has no single answer, and the header spans all of
/// it; the average is the colour most of the text sits on.
Color profileBannerInk(LinearGradient? gradient, Color? override) {
  if (override != null) return override;
  if (gradient == null || gradient.colors.isEmpty) {
    return const Color(0xFF3E312A);
  }
  var sum = 0.0;
  for (final c in gradient.colors) {
    sum += c.computeLuminance();
  }
  final mean = sum / gradient.colors.length;
  // 0.45 rather than the usual 0.5: this text is bold and fairly large, and
  // the dark brown holds up a little past the midpoint where white starts to
  // glare.
  return mean > 0.45 ? const Color(0xFF3E312A) : Colors.white;
}
