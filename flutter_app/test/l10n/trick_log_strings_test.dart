import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/l10n/app_localizations_de.dart';
import 'package:tichu_online/l10n/app_localizations_en.dart';
import 'package:tichu_online/l10n/app_localizations_ko.dart';

/// The Tichu trick log used to be written in Korean no matter who was reading
/// it — "드래곤", "A 페어", "폭탄(4)". These check that the strings that replaced
/// it exist in all three languages and put their values where they belong: a
/// placeholder that silently drops is the same bug in a new costume.

void main() {
  final locales = <String, L10n>{'ko': L10nKo(), 'en': L10nEn(), 'de': L10nDe()};

  group('every locale fills the trick-log placeholders', () {
    locales.forEach((tag, l10n) {
      test('$tag: the rank reaches the combination names', () {
        expect(l10n.trickPair('A'), contains('A'));
        expect(l10n.trickTriple('K'), contains('K'));
        expect(l10n.trickFullHouse('Q'), contains('Q'));
        expect(l10n.trickPhoenixOver('↑A'), contains('↑A'));
        expect(l10n.trickCallSuffix('7'), contains('7'));
      });

      test('$tag: a run carries both its rank and its length', () {
        final straight = l10n.trickStraight('J', 5);
        expect(straight, contains('J'));
        expect(straight, contains('5'));
        final steps = l10n.trickSteps('9', 6);
        expect(steps, contains('9'));
        expect(steps, contains('6'));
      });

      test('$tag: the special cards and bombs are named', () {
        for (final s in [
          l10n.trickCardDragon,
          l10n.trickCardPhoenix,
          l10n.trickCardMahjong,
          l10n.trickCardDog,
          l10n.trickBombFour,
          l10n.trickBombStraightFlush,
        ]) {
          expect(s.trim(), isNotEmpty);
        }
      });

      test('$tag: the shop sale window keeps its dates', () {
        expect(l10n.shopSaleWindow('08/01 ~ 08/31'), contains('08/01 ~ 08/31'));
      });
    });
  });

  test('the non-Korean locales are actually translated', () {
    final hangul = RegExp(r'[가-힣]');
    for (final l10n in [L10nEn(), L10nDe()]) {
      for (final s in [
        l10n.trickCardDragon,
        l10n.trickCardPhoenix,
        l10n.trickCardMahjong,
        l10n.trickCardDog,
        l10n.trickBombFour,
        l10n.trickBombStraightFlush,
        l10n.trickPair('A'),
        l10n.trickStraight('J', 5),
        l10n.trickCallSuffix('7'),
        l10n.shopSaleWindow('08/01'),
      ]) {
        expect(hangul.hasMatch(s), isFalse, reason: 'Korean left in "$s"');
      }
    }
  });
}
