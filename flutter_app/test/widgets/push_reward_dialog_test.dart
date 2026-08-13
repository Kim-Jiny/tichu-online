import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/l10n/app_localizations.dart';
import 'package:tichu_online/services/game_service.dart' show PushRewardOutcome;
import 'package:tichu_online/widgets/marketing_push.dart';

/// What the player sees after tapping a campaign notification.
///
/// This dialog is the entire confirmation that the tap did anything. The gold
/// goes straight into the wallet with no other announcement, so a campaign
/// that pays out silently is indistinguishable from one that failed — and the
/// support ticket that follows is "I tapped it and got nothing".

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: const Locale('ko'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('a gold reward names the amount', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPushRewardDialog(
              context,
              const PushRewardOutcome(rewardType: 'gold', gold: 50),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The number is the point. "You got a reward" leaves them checking the
    // wallet to find out whether anything happened.
    expect(find.textContaining('50'), findsOneWidget);
  });

  testWidgets('an item reward does not print the internal item key', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPushRewardDialog(
              context,
              const PushRewardOutcome(
                rewardType: 'item',
                itemKey: 'banner_pastel',
                days: 7,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // "banner_pastel" is a database key, not a thing a player recognises.
    expect(find.textContaining('banner_pastel'), findsNothing);
  });

  testWidgets('it cannot be dismissed by accident', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showPushRewardDialog(
              context,
              const PushRewardOutcome(rewardType: 'gold', gold: 50),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tapping outside is how a notification-driven popup gets dismissed before
    // it is read — the phone is already in the player's hand mid-tap. The
    // reward is only shown once, so a stray tap would lose the only notice
    // they get.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.textContaining('50'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('50'), findsNothing);
  });
}
