import 'package:flutter_test/flutter_test.dart';
import 'package:tichu_online/services/profile_store.dart';

void main() {
  test('ProfileStore caches profiles by nickname', () {
    final store = ProfileStore();
    final data = {
      'nickname': 'alice',
      'profile': {'wins': 10}
    };

    store.store(data);

    expect(store.current, isNotNull);
    expect(store.profileFor('alice'), isNotNull);
    expect(store.profileFor('alice')!['profile']['wins'], 10);
  });

  test('ProfileStore exposes cached profile during repeated request', () {
    final store = ProfileStore();
    store.store({
      'nickname': 'bob',
      'profile': {'wins': 3}
    });

    store.beginRequest('bob');

    expect(store.current, isNotNull);
    expect(store.current!['nickname'], 'bob');
  });

  test('ProfileStore clears current and cache', () {
    final store = ProfileStore();
    store.store({
      'nickname': 'carol',
      'profile': {'wins': 1}
    });

    store.clear();

    expect(store.current, isNull);
    expect(store.profileFor('carol'), isNull);
  });
}
