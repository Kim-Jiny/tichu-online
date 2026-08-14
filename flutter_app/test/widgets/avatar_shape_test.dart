import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/widgets/bot_avatar.dart';
import 'package:tichu_online/widgets/profile_avatar.dart';

/// Avatars are rounded squares, everywhere.
///
/// The three things that draw a face — the photo, the default silhouette, and
/// the bot art — are written in three different files and were three different
/// shapes at various points. When they disagree the table shows round bots
/// beside square players, or a seat changes shape the moment someone's photo
/// finishes loading, which reads as a glitch rather than as a style.
///
/// The radius is proportional, so these check the ratio rather than a pixel
/// count: a 24px row and a 92px seat have to read as the same shape.

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );

  /// The radius actually used to clip/paint, whichever way the widget does it.
  double? radiusOf(WidgetTester tester) {
    for (final clip in tester.widgetList<ClipRRect>(find.byType(ClipRRect))) {
      final r = clip.borderRadius;
      if (r is BorderRadius) return r.topLeft.x;
    }
    for (final d in tester.widgetList<DecoratedBox>(find.byType(DecoratedBox))) {
      final deco = d.decoration;
      if (deco is BoxDecoration && deco.borderRadius is BorderRadius) {
        return (deco.borderRadius! as BorderRadius).topLeft.x;
      }
    }
    for (final c in tester.widgetList<Container>(find.byType(Container))) {
      final deco = c.decoration;
      if (deco is BoxDecoration && deco.borderRadius is BorderRadius) {
        return (deco.borderRadius! as BorderRadius).topLeft.x;
      }
    }
    return null;
  }

  test('the radius keeps its proportion at every size', () {
    // 14 on a 60px avatar is where the shape was settled (the profile popup).
    expect(avatarCornerRadius(60), closeTo(14, 0.001));
    expect(avatarCornerRadius(30) / 30, closeTo(avatarCornerRadius(90) / 90, 0.0001));
    expect(avatarCornerRadius(24), greaterThan(0));
  });

  testWidgets('the default silhouette is a rounded square, not a circle', (t) async {
    await pump(t, const DefaultAvatar(size: 60));
    for (final c in t.widgetList<Container>(find.byType(Container))) {
      final deco = c.decoration;
      if (deco is BoxDecoration) {
        expect(deco.shape, BoxShape.rectangle,
            reason: 'a circle here makes photo-less seats a different shape');
      }
    }
    expect(radiusOf(t), closeTo(avatarCornerRadius(60), 0.001));
  });

  testWidgets('a photo is clipped to the same rounded square', (t) async {
    await pump(t, ProfileAvatar(
      photoUrl: 'https://example.invalid/a.webp',
      size: 60,
      fallback: const DefaultAvatar(size: 60),
    ));
    expect(find.byType(ClipOval), findsNothing);
    expect(radiusOf(t), closeTo(avatarCornerRadius(60), 0.001));
  });

  testWidgets('an explicit radius still wins — some surfaces have their own', (t) async {
    await pump(t, ProfileAvatar(
      photoUrl: 'https://example.invalid/a.webp',
      size: 60,
      borderRadius: 4,
      fallback: const DefaultAvatar(size: 60),
    ));
    expect(radiusOf(t), closeTo(4, 0.001));
  });

  testWidgets('a bordered avatar is rounded too, not a circle in a ring', (t) async {
    await pump(t, ProfileAvatar(
      photoUrl: 'https://example.invalid/a.webp',
      size: 60,
      border: Border.all(color: const Color(0xFF000000)),
      fallback: const DefaultAvatar(size: 60),
    ));
    for (final c in t.widgetList<Container>(find.byType(Container))) {
      final deco = c.decoration;
      if (deco is BoxDecoration && deco.border != null) {
        expect(deco.shape, BoxShape.rectangle);
        expect((deco.borderRadius! as BorderRadius).topLeft.x,
            closeTo(avatarCornerRadius(60), 0.001));
      }
    }
  });

  testWidgets('a bot wears the same shape as a person', (t) async {
    await pump(t, const BotAvatar(size: 60, name: '봇 1'));
    expect(find.byType(ClipOval), findsNothing);
    expect(radiusOf(t), closeTo(avatarCornerRadius(60), 0.001));
  });

  testWidgets('no photo, no bot, no ring — still the same shape', (t) async {
    // The three draw paths side by side at one size: if any of them drifts,
    // the seat visibly changes shape as data arrives.
    await pump(t, const DefaultAvatar(size: 42));
    final silhouette = radiusOf(t);
    await pump(t, const BotAvatar(size: 42, name: '봇 2'));
    final bot = radiusOf(t);
    await pump(t, ProfileAvatar(
      photoUrl: 'https://example.invalid/a.webp',
      size: 42,
      fallback: const DefaultAvatar(size: 42),
    ));
    final photo = radiusOf(t);
    expect(silhouette, closeTo(bot!, 0.001));
    expect(silhouette, closeTo(photo!, 0.001));
  });
}
