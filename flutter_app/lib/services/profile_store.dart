class ProfileStore {
  Map<String, dynamic>? _current;
  final Map<String, Map<String, dynamic>> _cache = {};

  Map<String, dynamic>? get current => _current;

  Map<String, dynamic>? profileFor(String nickname) => _cache[nickname];

  void beginRequest(String nickname) {
    _current = _cache[nickname];
  }

  void store(Map<String, dynamic> data) {
    _current = data;
    final nickname = data['nickname'] as String?;
    if (nickname == null || nickname.isEmpty) return;
    _cache[nickname] = Map<String, dynamic>.from(data);
  }

  void clear() {
    _current = null;
    _cache.clear();
  }
}
