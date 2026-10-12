import 'package:shared_preferences/shared_preferences.dart';

/// 인벤토리에서 "아직 안 본 새 아이템"을 가려낸다.
///
/// 쿠폰·우편·상점·이벤트 어디로 들어왔든, 서버는 그냥 보유 목록에 한 줄을
/// 더할 뿐이라 어느 칸에 무엇이 생겼는지 알려 줄 방법이 없었다. 기기에 "이미
/// 본 아이템" 표시를 들고 있다가 목록과 비교해, 처음 보는 것만 새것으로 친다.
///
/// 아이템 식별은 `item_key` + `acquired_at`. 기간 연장은 acquired_at 이 그대로라
/// 새것이 아니고, 소모 후 다시 받으면 acquired_at 이 달라 새것이 된다.
class InventoryNewTracker {
  InventoryNewTracker._(this._prefsKey, this._seen, this._initialized);

  final String _prefsKey;
  final Set<String> _seen;
  bool _initialized;

  static String sig(Map<String, dynamic> item) =>
      '${item['item_key']}|${item['acquired_at']}';

  static Future<InventoryNewTracker> load(String nickname) async {
    final key = 'inv_seen_$nickname';
    List<String>? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getStringList(key);
    } catch (_) {}
    return InventoryNewTracker._(key, {...?saved}, saved != null);
  }

  /// 처음 불러온 목록은 전부 "이미 본 것"으로 깔고, 이후엔 사라진 항목만
  /// 정리한다. 바뀌었으면 true.
  bool sync(List<Map<String, dynamic>> items) {
    final current = items.map(sig).toSet();
    if (!_initialized) {
      _initialized = true;
      _seen
        ..clear()
        ..addAll(current);
      _save();
      return true;
    }
    final before = _seen.length;
    _seen.retainAll(current);
    if (_seen.length != before) {
      _save();
      return true;
    }
    return false;
  }

  bool isNew(Map<String, dynamic> item) =>
      _initialized && !_seen.contains(sig(item));

  bool anyNew(Iterable<Map<String, dynamic>> items) => items.any(isNew);

  /// 이 칸의 새것을 본 것으로 친다. 바뀌었으면 true.
  bool markSeen(Iterable<Map<String, dynamic>> items) {
    var changed = false;
    for (final i in items) {
      if (_seen.add(sig(i))) changed = true;
    }
    if (changed) _save();
    return changed;
  }

  Future<void> _save() async {
    try {
      (await SharedPreferences.getInstance()).setStringList(
        _prefsKey,
        _seen.toList(),
      );
    } catch (_) {}
  }
}
