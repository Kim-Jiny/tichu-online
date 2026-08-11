import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/services/network_service.dart';

/// When are we allowed to call a socket dead?
///
/// Both rules here were written for a phone the OS suspends, and both of them
/// misfire in a browser, where a hidden tab keeps its socket open but freezes
/// our timers. The symptom was a web client that reconnected every single time
/// you came back to the tab.

void main() {
  group('coming back to the foreground', () {
    test('a suspended app assumes the socket is gone', () {
      expect(
        NetworkService.shouldAssumeDeadAfterResume(
          const Duration(seconds: 30),
          isWeb: false,
        ),
        isTrue,
      );
    });

    test('a short pause is probed, not assumed', () {
      expect(
        NetworkService.shouldAssumeDeadAfterResume(
          const Duration(seconds: 3),
          isWeb: false,
        ),
        isFalse,
      );
    });

    test('a tab you left for an hour still gets the benefit of the doubt', () {
      // The browser answers the server's protocol-level pings for us the whole
      // time it is hidden, so length of absence proves nothing here.
      expect(
        NetworkService.shouldAssumeDeadAfterResume(
          const Duration(hours: 1),
          isWeb: true,
        ),
        isFalse,
      );
    });
  });

  group('heartbeat verdict', () {
    test('a punctual tick with no pong condemns the socket', () {
      expect(
        NetworkService.heartbeatSaysDead(
          sinceLastTick: const Duration(seconds: 5),
          sinceLastPong: const Duration(seconds: 20),
        ),
        isTrue,
      );
    });

    test('a fresh pong is fine', () {
      expect(
        NetworkService.heartbeatSaysDead(
          sinceLastTick: const Duration(seconds: 5),
          sinceLastPong: const Duration(seconds: 4),
        ),
        isFalse,
      );
    });

    test('the first tick after a frozen timer condemns nothing', () {
      // Throttled to one a minute while the tab was hidden: of course no pong
      // arrived — we never sent a ping. This tick pings; the next one judges.
      expect(
        NetworkService.heartbeatSaysDead(
          sinceLastTick: const Duration(seconds: 60),
          sinceLastPong: const Duration(seconds: 60),
        ),
        isFalse,
      );
    });

    test('the tick after that does condemn it, if the ping went unanswered', () {
      expect(
        NetworkService.heartbeatSaysDead(
          sinceLastTick: const Duration(seconds: 5),
          sinceLastPong: const Duration(seconds: 65),
        ),
        isTrue,
      );
    });

    test('never having seen a pong is not proof of death', () {
      expect(
        NetworkService.heartbeatSaysDead(
          sinceLastTick: const Duration(seconds: 5),
          sinceLastPong: null,
        ),
        isFalse,
      );
    });
  });
}
