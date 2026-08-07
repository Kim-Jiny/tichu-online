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

  /// Point a stored profile's photo at [url] (null clears it).
  ///
  /// A stored profile is a snapshot from the moment it was fetched, so after
  /// its owner uploads or removes a photo it still carries the old one. The
  /// popup reads the photo from here, so deleting your own photo cleared it
  /// everywhere on screen except the popup you deleted it from — that one
  /// still had the stale URL to fall back on.
  void setPhotoUrl(String nickname, String? url) {
    _patchPhoto(_cache[nickname], url);
    final cur = _current;
    // `_current` is the response object itself, not the cached copy, so the
    // two need patching separately even when they describe the same person.
    if (cur != null && cur['nickname'] == nickname) _patchPhoto(cur, url);
  }

  static void _patchPhoto(Map<String, dynamic>? entry, String? url) {
    final inner = entry?['profile'];
    if (inner is! Map) return;
    // Replaced rather than mutated: the cached copy is shallow, so the inner
    // map may be shared with `_current` or with a caller that already read it.
    entry!['profile'] = Map<String, dynamic>.from(inner)..['photoUrl'] = url;
  }

  void clear() {
    _current = null;
    _cache.clear();
  }
}
