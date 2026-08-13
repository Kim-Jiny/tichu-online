import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/title_chip.dart';

/// Title colours on top of a banner.
///
/// Every title colour in the catalogue was picked against the app's cream
/// background. A dark banner swallows the darker half of them — the near-black
/// pirate is the worst, but the deep teal tactician and the crimson ace go too
/// — while the same palette stays perfectly good everywhere else. So the
/// colours are lightened for dark fills rather than rewritten.
///
/// Lightened, not replaced: the colour is how a title is recognised, and
/// forcing them all to white would make twenty titles look like one. These
/// tests are what stop a future "just use white" from passing review.

void main() {
  const onDark = Colors.white; // what reads on a dark banner
  const onLight = Color(0xFF3E312A); // what reads on a pale one

  test('with no banner, the palette is untouched', () {
    for (final key in ['title_pirate', 'title_lucky', 'title_king']) {
      expect(titleColorFor(key), titleColorFor(key, onInk: null));
    }
  });

  test('a pale banner also leaves it untouched', () {
    // Those banners take dark text, which is the condition the palette was
    // designed for in the first place.
    expect(
      titleColorFor('title_pirate', onInk: onLight),
      titleColorFor('title_pirate'),
    );
  });

  test('the near-black title is brought up on a dark banner', () {
    final base = titleColorFor('title_pirate');
    final lifted = titleColorFor('title_pirate', onInk: onDark);
    expect(lifted, isNot(base));
    expect(
      lifted.computeLuminance(),
      greaterThan(base.computeLuminance()),
      reason: '#37474F on a near-black gradient is invisible',
    );
  });

  test('and it keeps its hue, so titles stay distinguishable', () {
    final base = HSLColor.fromColor(titleColorFor('title_pirate'));
    final lifted = HSLColor.fromColor(
      titleColorFor('title_pirate', onInk: onDark),
    );
    expect((lifted.hue - base.hue).abs(), lessThan(1.0));
  });

  test('two different titles stay two different colours', () {
    final a = titleColorFor('title_pirate', onInk: onDark);
    final b = titleColorFor('title_ace', onInk: onDark);
    expect(a, isNot(b), reason: 'lightening must not collapse the palette');
  });

  test('a title already bright enough is left alone', () {
    // Pure yellow has an HSL lightness of only 0.5 and is one of the
    // brightest colours there is. Judging by lightness washed it out to cream.
    final base = titleColorFor('title_lucky');
    expect(titleColorFor('title_lucky', onInk: onDark), base);
  });

  test('the lift is idempotent', () {
    final once = lightenForDarkBackground(const Color(0xFF37474F));
    expect(lightenForDarkBackground(once), once);
  });

  test('every catalogue title clears a readable floor on dark', () {
    // The specific keys matter less than the guarantee: no title may come out
    // of this too dark to read on a near-black banner.
    const keys = [
      'title_sweet', 'title_steady', 'title_flash_30d', 'title_dragon',
      'title_phoenix', 'title_pirate', 'title_tactician', 'title_lucky',
      'title_bluffer', 'title_ace', 'title_king', 'title_rookie',
      'title_veteran', 'title_sensitive', 'title_shadow', 'title_flame',
      'title_ice', 'title_crown', 'title_diamond', 'title_ghost',
    ];
    for (final key in keys) {
      final c = titleColorFor(key, onInk: onDark);
      expect(
        c.computeLuminance(),
        greaterThanOrEqualTo(0.34),
        reason: '$key is still too dark to read on a dark banner',
      );
    }
  });
}
