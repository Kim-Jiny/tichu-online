import 'dart:async';

class RestoreSyncTracker {
  Completer<void>? _pending;

  bool get isWaiting => _pending != null;

  Future<bool> begin({
    Duration timeout = const Duration(seconds: 3),
    required void Function() request,
  }) async {
    if (_pending != null) {
      try {
        await _pending!.future.timeout(timeout);
        return true;
      } catch (_) {
        return false;
      }
    }

    final completer = Completer<void>();
    _pending = completer;
    request();

    try {
      await completer.future.timeout(timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      if (identical(_pending, completer)) {
        _pending = null;
      }
    }
  }

  void complete() {
    final completer = _pending;
    if (completer == null || completer.isCompleted) return;
    completer.complete();
    _pending = null;
  }
}
