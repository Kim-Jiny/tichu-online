// 서버 CardValidator.js 의 조합 판정을 그대로 옮긴 것. 화면에서 "낼 수 있는 패인가"를
// 미리 알려 주기 위한 용도이며, 최종 판정은 항상 서버가 한다.
// (소원 의무는 서버만 정확히 알 수 있어 여기서는 다루지 않는다.)

class TichuCombo {
  final String type;
  final int length;
  final double value;
  final bool isPhoenix;
  const TichuCombo(this.type, this.length, this.value, {this.isPhoenix = false});

  bool get isBomb => type == 'bomb_four' || type == 'bomb_straight_flush';
}

const _rankValues = {
  '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
  '10': 10, 'J': 11, 'Q': 12, 'K': 13, 'A': 14,
};

int _value(String id) {
  switch (id) {
    case 'special_bird':
      return 1;
    case 'special_dog':
      return 0;
    case 'special_phoenix':
      return -1;
    case 'special_dragon':
      return 15;
  }
  return _rankValues[id.split('_')[1]] ?? 0;
}

bool _normal(String id) => !id.startsWith('special_');

Map<int, int> _counts(List<String> ids) {
  final m = <int, int>{};
  for (final id in ids) {
    m[_value(id)] = (m[_value(id)] ?? 0) + 1;
  }
  return m;
}

/// 조합을 판정한다. 만들 수 없는 조합이면 null.
TichuCombo? tichuComboOf(List<String> ids) {
  if (ids.isEmpty) return null;
  if (ids.length == 1 && ids[0] == 'special_dog') {
    return const TichuCombo('dog', 1, 0);
  }
  if (ids.contains('special_dog')) return null;

  final hasPhoenix = ids.contains('special_phoenix');
  final normals = ids.where((c) => c != 'special_phoenix').toList();
  final n = ids.length;

  if (n == 1) {
    final c = ids[0];
    if (c == 'special_dragon') return const TichuCombo('single', 1, 15);
    if (c == 'special_phoenix') {
      return const TichuCombo('single', 1, -1, isPhoenix: true);
    }
    return TichuCombo('single', 1, _value(c).toDouble());
  }
  if (n == 2) return _pair(normals, hasPhoenix);
  if (n == 3) return _triple(normals, hasPhoenix);
  if (n == 4) {
    if (!hasPhoenix) {
      final v = normals.map(_value).toList();
      if (v.every((x) => x == v[0]) && _normal(normals[0])) {
        return TichuCombo('bomb_four', 4, v[0].toDouble());
      }
    }
    return _steps(normals, hasPhoenix, n);
  }
  if (!hasPhoenix) {
    final sf = _straightFlush(normals);
    if (sf != null) return sf;
  }
  if (n == 5) {
    final fh = _fullHouse(normals, hasPhoenix);
    if (fh != null) return fh;
  }
  return _straight(normals, hasPhoenix, n) ?? _steps(normals, hasPhoenix, n);
}

TichuCombo? _pair(List<String> normals, bool hasPhoenix) {
  if (hasPhoenix && normals.length == 1) {
    final c = normals[0];
    if (c == 'special_bird' || c == 'special_dragon') return null;
    return TichuCombo('pair', 2, _value(c).toDouble());
  }
  if (normals.length == 2) {
    if (normals.contains('special_bird') || normals.contains('special_dragon')) {
      return null;
    }
    if (_value(normals[0]) == _value(normals[1])) {
      return TichuCombo('pair', 2, _value(normals[0]).toDouble());
    }
  }
  return null;
}

TichuCombo? _triple(List<String> normals, bool hasPhoenix) {
  if (hasPhoenix) {
    if (normals.length == 2 &&
        _value(normals[0]) == _value(normals[1]) &&
        _normal(normals[0]) &&
        _normal(normals[1])) {
      return TichuCombo('triple', 3, _value(normals[0]).toDouble());
    }
  } else if (normals.length == 3) {
    final v = normals.map(_value).toList();
    if (v[0] == v[1] && v[1] == v[2] && _normal(normals[0])) {
      return TichuCombo('triple', 3, v[0].toDouble());
    }
  }
  return null;
}

TichuCombo? _straightFlush(List<String> cards) {
  if (cards.length < 5) return null;
  final suits = cards.map((c) => c.split('_')[0]).toList();
  if (!suits.every((s) => s == suits[0])) return null;
  if (cards.any((c) => c.startsWith('special_') && c != 'special_bird')) {
    return null;
  }
  final v = cards.map(_value).toList()..sort();
  for (var i = 1; i < v.length; i++) {
    if (v[i] != v[i - 1] + 1) return null;
  }
  return TichuCombo('bomb_straight_flush', cards.length, v.last.toDouble());
}

TichuCombo? _fullHouse(List<String> normals, bool hasPhoenix) {
  final e = _counts(normals).entries.toList();
  if (e.length != 2) return null;
  final c1 = e[0].value, c2 = e[1].value;
  final v1 = e[0].key, v2 = e[1].key;
  if (hasPhoenix) {
    if (c1 == 3 && c2 == 1) return TichuCombo('full_house', 5, v1.toDouble());
    if (c1 == 1 && c2 == 3) return TichuCombo('full_house', 5, v2.toDouble());
    if (c1 == 2 && c2 == 2) {
      return TichuCombo('full_house', 5, (v1 > v2 ? v1 : v2).toDouble());
    }
  } else {
    if (c1 == 3 && c2 == 2) return TichuCombo('full_house', 5, v1.toDouble());
    if (c1 == 2 && c2 == 3) return TichuCombo('full_house', 5, v2.toDouble());
  }
  return null;
}

TichuCombo? _straight(List<String> normals, bool hasPhoenix, int total) {
  if (total < 5) return null;
  if (normals.contains('special_dragon') || normals.contains('special_dog')) {
    return null;
  }
  final v = normals.map(_value).toList()..sort();
  final unique = v.toSet().toList()..sort();
  if (unique.length != v.length) return null;
  if (!hasPhoenix) {
    if (unique.length != total) return null;
    for (var i = 1; i < unique.length; i++) {
      if (unique[i] != unique[i - 1] + 1) return null;
    }
    return TichuCombo('straight', total, unique.last.toDouble());
  }
  if (unique.length + 1 != total) return null;
  var gaps = 0;
  for (var i = 1; i < unique.length; i++) {
    final d = unique[i] - unique[i - 1];
    if (d == 1) continue;
    if (d == 2) {
      gaps++;
    } else {
      return null;
    }
  }
  if (gaps > 1) return null;
  var high = unique.last;
  if (gaps == 0) {
    high = unique.last + 1;
    if (high > 14) high = unique.last;
  }
  return TichuCombo('straight', total, high.toDouble());
}

TichuCombo? _steps(List<String> normals, bool hasPhoenix, int total) {
  if (total % 2 != 0 || total < 4) return null;
  final numPairs = total ~/ 2;
  final entries = _counts(normals).entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final pairs = <int>[];
  var used = false;
  for (final e in entries) {
    if (e.value == 2) {
      pairs.add(e.key);
    } else if (hasPhoenix && e.value == 1 && !used) {
      pairs.add(e.key);
      used = true;
    } else {
      return null;
    }
  }
  if (pairs.length != numPairs) return null;
  for (var i = 1; i < pairs.length; i++) {
    if (pairs[i] != pairs[i - 1] + 1) return null;
  }
  return TichuCombo('steps', total, pairs.last.toDouble());
}

bool _bombBeats(TichuCombo cur, TichuCombo next) {
  if (cur.type == 'bomb_four' && next.type == 'bomb_straight_flush') return true;
  if (cur.type == 'bomb_straight_flush' && next.type == 'bomb_four') return false;
  if (cur.type == 'bomb_straight_flush') {
    if (next.length != cur.length) return next.length > cur.length;
  }
  return next.value > cur.value;
}

bool tichuCanBeat(TichuCombo cur, TichuCombo next) {
  if (next.isBomb) return cur.isBomb ? _bombBeats(cur, next) : true;
  if (cur.isBomb) return false;
  if (cur.type != next.type || cur.length != next.length) return false;
  return next.value > cur.value;
}

/// 선택한 패를 지금 낼 수 있는가.
/// [trickType]/[trickLength]/[trickValue] 가 null 이면 새 트릭의 선공이다.
/// [myTurn] 이 아니면 폭탄만 끼어들 수 있다.
bool tichuCanPlay(
  List<String> selected, {
  required bool myTurn,
  String? trickType,
  int trickLength = 0,
  double trickValue = 0,
}) {
  final combo = tichuComboOf(selected);
  if (combo == null) return false;
  final hasTrick = trickType != null;
  final cur = hasTrick ? TichuCombo(trickType, trickLength, trickValue) : null;

  if (!myTurn) {
    if (!combo.isBomb || cur == null) return false;
    return tichuCanBeat(cur, combo);
  }
  if (combo.type == 'dog') return !hasTrick;
  if (cur == null) return true;
  var c = combo;
  if (combo.isPhoenix) {
    if (cur.value == 15) return false;
    c = TichuCombo('single', 1, cur.value + 0.5);
  }
  return tichuCanBeat(cur, c);
}
