import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/main.dart' show pendingCampaignTaps;

/// The queue a tapped campaign notification lands in.
///
/// It has to WAKE somebody, which is why it is a notifier and not a plain set.
/// A tap arrives in one of two states, and they are not alike:
///
///  - cold start: the tap is known before runApp, earlier than any widget, so
///    it has to be readable by whatever mounts later;
///  - already running in the background: nothing else about the app changes —
///    the socket stays up, no state moves — so a passive collection would sit
///    there unread and the reward would never be claimed. That case was real
///    and shipped-adjacent; the listener is what fixes it.

void main() {
  setUp(() => pendingCampaignTaps.value = const []);

  test('adding a tap notifies a listener', () {
    var woken = 0;
    void listener() => woken++;
    pendingCampaignTaps.addListener(listener);
    addTearDown(() => pendingCampaignTaps.removeListener(listener));

    pendingCampaignTaps.value = [...pendingCampaignTaps.value, 7];
    expect(woken, 1, reason: 'a tap that wakes nobody is a reward never paid');
    expect(pendingCampaignTaps.value, [7]);
  });

  test('a tap that arrived before anyone was listening is still readable', () {
    // The cold-start case: the value is set before the widget exists, and
    // whatever mounts later reads it rather than waiting for a notification
    // that already happened.
    pendingCampaignTaps.value = const [11];
    var woken = 0;
    void listener() => woken++;
    pendingCampaignTaps.addListener(listener);
    addTearDown(() => pendingCampaignTaps.removeListener(listener));

    expect(pendingCampaignTaps.value, [11]);
    expect(woken, 0, reason: 'listeners fire on change, not on attach');
  });

  test('draining it notifies too, so a stale queue cannot be re-claimed', () {
    pendingCampaignTaps.value = const [3];
    var woken = 0;
    void listener() => woken++;
    pendingCampaignTaps.addListener(listener);
    addTearDown(() => pendingCampaignTaps.removeListener(listener));

    pendingCampaignTaps.value = const [];
    expect(woken, 1);
    expect(pendingCampaignTaps.value, isEmpty);
  });

  test('assigning an equal list does not spin', () {
    // ValueNotifier compares by identity for lists, so replacing the value
    // always notifies — including with an empty list. The drain must therefore
    // not run inside its own listener without a guard, or it loops.
    pendingCampaignTaps.value = const [];
    var woken = 0;
    void listener() => woken++;
    pendingCampaignTaps.addListener(listener);
    addTearDown(() => pendingCampaignTaps.removeListener(listener));

    // Same const instance: Dart canonicalises it, so this is identical and
    // must not fire.
    pendingCampaignTaps.value = const [];
    expect(woken, 0);
  });
}
