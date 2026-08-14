import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/main.dart'
    show pendingCampaignTaps, pendingPushOpens, recordPushTap;

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
  setUp(() {
    pendingCampaignTaps.value = const [];
    pendingPushOpens.value = const [];
  });

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

  group('어떤 큐로 가는가', () {
    // The routing decides whether a tap pays gold or merely counts. Swapping
    // the two is invisible in testing and shows up as "I tapped the reward
    // notification and got nothing".
    test('보상 캠페인은 지급 큐로', () {
      recordPushTap({'type': 'campaign', 'campaignId': '42'});
      expect(pendingCampaignTaps.value, [42]);
      expect(pendingPushOpens.value, isEmpty);
    });

    test('어드민 단체 발송은 집계 큐로', () {
      recordPushTap({'type': 'broadcast', 'pushId': '7'});
      expect(pendingCampaignTaps.value, isEmpty);
      expect(pendingPushOpens.value, [(kind: 'broadcast', id: 7)]);
    });

    test('개별 알림도 집계 큐로, 종류를 구분해서', () {
      recordPushTap({'type': 'log', 'pushId': '7'});
      expect(pendingPushOpens.value, [(kind: 'log', id: 7)]);
    });

    test('같은 번호라도 종류가 다르면 다른 알림이다', () {
      recordPushTap({'type': 'broadcast', 'pushId': '5'});
      recordPushTap({'type': 'log', 'pushId': '5'});
      expect(pendingPushOpens.value.length, 2);
    });

    test('같은 알림을 두 번 눌러도 한 번만 쌓인다', () {
      recordPushTap({'type': 'log', 'pushId': '9'});
      recordPushTap({'type': 'log', 'pushId': '9'});
      expect(pendingPushOpens.value.length, 1);
    });

    test('아무 표식 없는 알림은 무시한다', () {
      // A plain notification with no data payload — nothing to report, and
      // inventing an id would corrupt someone else's count.
      recordPushTap({});
      recordPushTap({'type': 'broadcast'});
      recordPushTap({'type': 'log', 'pushId': 'not-a-number'});
      expect(pendingCampaignTaps.value, isEmpty);
      expect(pendingPushOpens.value, isEmpty);
    });
  });
}
