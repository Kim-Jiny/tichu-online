import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tichu_online/services/inventory_new_tracker.dart';

Map<String, dynamic> item(String key, [String at = 't1']) => {
  'item_key': key,
  'acquired_at': at,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('처음 불러온 목록은 전부 본 것으로 깔아서 새것이 없다', () async {
    final t = await InventoryNewTracker.load('a');
    t.sync([item('x'), item('y')]);
    expect(t.anyNew([item('x'), item('y')]), isFalse);
  });

  test('이후 들어온 아이템만 새것이고, 보면 지워진다', () async {
    final t = await InventoryNewTracker.load('a');
    t.sync([item('x')]);
    final next = [item('x'), item('banner_new', 't2')];
    t.sync(next);
    expect(t.isNew(next[1]), isTrue);
    expect(t.isNew(next[0]), isFalse);
    expect(t.markSeen([next[1]]), isTrue);
    expect(t.anyNew(next), isFalse);
    expect(t.markSeen([next[1]]), isFalse);
  });

  test('다시 받은 아이템(acquired_at 이 다름)은 새것이다', () async {
    final t = await InventoryNewTracker.load('a');
    t.sync([item('x', 't1')]);
    expect(t.isNew(item('x', 't9')), isTrue);
  });

  test('앱을 다시 열어도 본 표시가 남는다', () async {
    final t = await InventoryNewTracker.load('a');
    t.sync([item('x')]);
    t.markSeen([item('y')]);
    await Future<void>.delayed(Duration.zero);
    final again = await InventoryNewTracker.load('a');
    expect(again.isNew(item('y')), isFalse);
    expect(again.isNew(item('z')), isTrue);
  });

  test('계정마다 따로 센다', () async {
    final a = await InventoryNewTracker.load('a');
    a.sync([item('x')]);
    await Future<void>.delayed(Duration.zero);
    final b = await InventoryNewTracker.load('b');
    b.sync([item('y')]);
    expect(b.isNew(item('x')), isTrue);
  });
}
